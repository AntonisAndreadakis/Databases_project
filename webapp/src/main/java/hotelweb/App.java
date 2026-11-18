package hotelweb;

import static hotelweb.Html.esc;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.Base64;
import java.util.List;
import java.util.OptionalInt;

import org.eclipse.jetty.http.HttpCookie;
import org.mindrot.jbcrypt.BCrypt;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import hotelweb.Html.Flash;
import io.javalin.Javalin;
import io.javalin.http.Context;
import io.javalin.http.HandlerType;
import io.javalin.http.HttpStatus;
import io.javalin.http.staticfiles.Location;

/**
 * Web version of the console application of phase B (DbApp): the same functions
 * as its menus, as web pages behind a login.
 */
public final class App {

	private static final Logger log = LoggerFactory.getLogger(App.class);

	private static final String SESSION_USER = "user";
	private static final String SESSION_CSRF = "csrf";
	private static final String SESSION_FLASH = "flash";

	private static final String LOGIN_FAILED = "Λάθος όνομα χρήστη ή κωδικός.";

	private static final SecureRandom RANDOM = new SecureRandom();

	private final Db db;
	/** Hash checked when the username is unknown, so that both failures take the same time. */
	private final String dummyHash = BCrypt.hashpw(randomToken(), BCrypt.gensalt());

	private App(Db db) {
		this.db = db;
	}

	public static void main(String[] args) {
		Config config;
		try {
			config = Config.fromEnv();
		} catch (IllegalStateException e) {
			log.error(e.getMessage());
			System.exit(2);
			return;
		}
		Db db = new Db(config);
		try {
			db.waitUntilReachable(60_000);
		} catch (SQLException e) {
			log.error("Could not connect to the database: {}", firstLine(e.getMessage()));
			System.exit(1);
			return;
		}
		createFirstUser(db, config);
		new App(db).start(config.port());
	}

	/** If there is no user yet, creates the one given in the environment. The password is never logged. */
	private static void createFirstUser(Db db, Config config) {
		try {
			if (db.countUsers() > 0) {
				return;
			}
			if (config.adminUser() == null || config.adminPassword() == null) {
				log.warn("Table app_user is empty and APP_ADMIN_USER / APP_ADMIN_PASSWORD are not set: nobody can log in.");
				return;
			}
			db.insertUser(config.adminUser(), BCrypt.hashpw(config.adminPassword(), BCrypt.gensalt()));
			log.info("Created the first user \"{}\".", config.adminUser());
		} catch (SQLException e) {
			log.error("Could not prepare the first user: {}", firstLine(e.getMessage()));
		}
	}

	private void start(int port) {
		Javalin app = Javalin.create(config -> {
			config.showJavalinBanner = false;
			config.staticFiles.add(files -> {
				files.hostedPath = "/static";
				files.directory = "/public";
				files.location = Location.CLASSPATH;
			});
			config.jetty.modifyServletContextHandler(handler -> {
				handler.getSessionHandler().setHttpOnly(true);
				handler.getSessionHandler().setSameSite(HttpCookie.SameSite.LAX);
			});
		});

		app.before(this::guard);

		app.get("/login", this::loginForm);
		app.post("/login", this::login);
		app.post("/logout", this::logout);
		app.get("/", this::home);
		app.get("/hotels/{id}", this::hotel);
		app.post("/hotels/{id}/roombookings/update", this::updateRoomBooking);
		app.post("/hotels/{id}/bookings", this::createBooking);

		app.exception(SQLException.class, (e, ctx) -> {
			log.error("Database error on {} {}: {}", ctx.method(), ctx.path(), firstLine(e.getMessage()));
			ctx.status(HttpStatus.INTERNAL_SERVER_ERROR);
			render(ctx, "Σφάλμα", Html.message(false, "Η βάση δεδομένων απέρριψε το αίτημα: " + firstLine(e.getMessage()))
					+ "<p><a href=\"/\">Επιστροφή στην αρχική</a></p>");
		});
		app.exception(Exception.class, (e, ctx) -> {
			log.error("Unexpected error on {} {}", ctx.method(), ctx.path(), e);
			ctx.status(HttpStatus.INTERNAL_SERVER_ERROR);
			render(ctx, "Σφάλμα", Html.message(false, "Κάτι πήγε στραβά. Δοκιμάστε ξανά.")
					+ "<p><a href=\"/\">Επιστροφή στην αρχική</a></p>");
		});
		app.error(HttpStatus.NOT_FOUND, ctx -> {
			if (ctx.result() == null) {
				render(ctx, "Δεν βρέθηκε", Html.message(false, "Η σελίδα δεν βρέθηκε.")
						+ "<p><a href=\"/\">Επιστροφή στην αρχική</a></p>");
			}
		});

		app.start("0.0.0.0", port);
	}

	// ---------------------------------------------------------------------------------
	// Login, session, CSRF
	// ---------------------------------------------------------------------------------

	/** Runs before every request: security headers, login check, CSRF check of every POST. */
	private void guard(Context ctx) {
		ctx.header("X-Content-Type-Options", "nosniff");
		ctx.header("X-Frame-Options", "DENY");
		ctx.header("Referrer-Policy", "same-origin");
		ctx.header("Content-Security-Policy",
				"default-src 'none'; style-src 'self'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");

		String path = ctx.path();
		if (path.startsWith("/static/")) {
			return;
		}
		ctx.header("Cache-Control", "no-store");

		boolean loginPage = path.equals("/login");
		if (!loginPage && currentUser(ctx) == null) {
			ctx.redirect("/login", HttpStatus.SEE_OTHER);
			ctx.skipRemainingHandlers();
			return;
		}
		if (ctx.method() == HandlerType.POST && !csrfMatches(ctx)) {
			ctx.status(HttpStatus.FORBIDDEN);
			render(ctx, "Μη έγκυρο αίτημα", Html.message(false,
					"Το αίτημα απορρίφθηκε γιατί η φόρμα έληξε ή δεν είναι έγκυρη. Φορτώστε ξανά τη σελίδα και δοκιμάστε πάλι.")
					+ "<p><a href=\"/\">Επιστροφή</a></p>");
			ctx.skipRemainingHandlers();
		}
	}

	private static String currentUser(Context ctx) {
		// Do not create a session just to look for the user.
		if (ctx.req().getSession(false) == null) {
			return null;
		}
		return ctx.sessionAttribute(SESSION_USER);
	}

	private static String existingCsrfToken(Context ctx) {
		if (ctx.req().getSession(false) == null) {
			return null;
		}
		return ctx.sessionAttribute(SESSION_CSRF);
	}

	/** Returns the CSRF token of the session, creating the session and the token when missing. */
	private static String csrfToken(Context ctx) {
		String token = existingCsrfToken(ctx);
		if (token == null) {
			token = randomToken();
			ctx.sessionAttribute(SESSION_CSRF, token);
		}
		return token;
	}

	private static boolean csrfMatches(Context ctx) {
		String expected = existingCsrfToken(ctx);
		String given = ctx.formParam("_csrf");
		if (expected == null || given == null) {
			return false;
		}
		return MessageDigest.isEqual(expected.getBytes(StandardCharsets.UTF_8), given.getBytes(StandardCharsets.UTF_8));
	}

	private static String randomToken() {
		byte[] bytes = new byte[32];
		RANDOM.nextBytes(bytes);
		return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
	}

	private void loginForm(Context ctx) {
		if (currentUser(ctx) != null) {
			ctx.redirect("/", HttpStatus.SEE_OTHER);
			return;
		}
		renderLogin(ctx, "", null);
	}

	private void renderLogin(Context ctx, String username, String error) {
		String body = "<section class=\"card login\">\n"
				+ "<h1>Σύνδεση</h1>\n"
				+ (error == null ? "" : Html.message(false, error) + "\n")
				+ "<form method=\"post\" action=\"/login\" class=\"stack\">\n"
				+ Html.csrfField(csrfToken(ctx)) + "\n"
				+ "<label>Όνομα χρήστη"
				+ "<input type=\"text\" name=\"username\" value=\"" + esc(username) + "\" maxlength=\"50\""
				+ " autocomplete=\"username\" autocapitalize=\"none\" required autofocus></label>\n"
				+ "<label>Κωδικός"
				+ "<input type=\"password\" name=\"password\" autocomplete=\"current-password\" required></label>\n"
				+ "<button type=\"submit\">Σύνδεση</button>\n"
				+ "</form>\n</section>";
		ctx.html(Html.page("Σύνδεση", null, null, takeFlash(ctx), body));
	}

	private void login(Context ctx) throws SQLException {
		String username = param(ctx.formParam("username"));
		String password = ctx.formParam("password");
		if (password == null) {
			password = "";
		}
		String hash = username.isEmpty() || username.length() > 50 ? null : db.findPasswordHash(username);
		boolean ok;
		if (hash == null) {
			BCrypt.checkpw(password, dummyHash);
			ok = false;
		} else {
			try {
				ok = BCrypt.checkpw(password, hash);
			} catch (IllegalArgumentException e) {
				ok = false; // the stored value is not a BCrypt hash
			}
		}
		if (!ok) {
			ctx.status(HttpStatus.UNAUTHORIZED);
			renderLogin(ctx, username, LOGIN_FAILED);
			return;
		}
		ctx.req().getSession(true);
		ctx.req().changeSessionId();
		ctx.sessionAttribute(SESSION_USER, username);
		ctx.sessionAttribute(SESSION_CSRF, randomToken());
		ctx.redirect("/", HttpStatus.SEE_OTHER);
	}

	private void logout(Context ctx) {
		var session = ctx.req().getSession(false);
		if (session != null) {
			session.invalidate();
		}
		ctx.redirect("/login", HttpStatus.SEE_OTHER);
	}

	// ---------------------------------------------------------------------------------
	// Page 1: search hotels by name prefix
	// ---------------------------------------------------------------------------------

	private void home(Context ctx) throws SQLException {
		String prefix = param(ctx.queryParam("q"));
		List<Db.Hotel> hotels = db.searchHotels(prefix);

		StringBuilder body = new StringBuilder();
		body.append("<h1>Αναζήτηση ξενοδοχείου</h1>\n")
				.append("<form method=\"get\" action=\"/\" class=\"row\">\n")
				.append("<label>Αρχικά γράμματα του ονόματος")
				.append("<input type=\"search\" name=\"q\" value=\"").append(esc(prefix)).append("\" maxlength=\"100\" autofocus></label>\n")
				.append("<button type=\"submit\">Αναζήτηση</button>\n</form>\n");
		if (hotels.isEmpty()) {
			body.append(Html.message(false, "Κανένα ξενοδοχείο δεν αρχίζει από «" + prefix + "»."));
		} else {
			body.append("<p class=\"count\">").append(hotels.size()).append(hotels.size() == 1 ? " ξενοδοχείο" : " ξενοδοχεία").append("</p>\n")
					.append("<div class=\"scroll\"><table>\n<thead><tr><th>#</th><th>Όνομα</th><th>Πόλη</th><th>Χώρα</th></tr></thead>\n<tbody>\n");
			int number = 0;
			for (Db.Hotel h : hotels) {
				number++;
				body.append("<tr><td class=\"num\">").append(number).append("</td>")
						.append("<td><a href=\"/hotels/").append(h.id()).append("\">").append(esc(h.name())).append("</a></td>")
						.append("<td>").append(esc(h.city())).append("</td>")
						.append("<td>").append(esc(h.country())).append("</td></tr>\n");
			}
			body.append("</tbody>\n</table></div>");
		}
		render(ctx, "Αναζήτηση ξενοδοχείου", body.toString());
	}

	// ---------------------------------------------------------------------------------
	// Page 2: one hotel, with the three functions of the hotel menu
	// ---------------------------------------------------------------------------------

	private void hotel(Context ctx) throws SQLException {
		Integer hotelId = parseInt(ctx.pathParam("id"));
		Db.Hotel hotel = hotelId == null ? null : db.findHotel(hotelId);
		if (hotel == null) {
			ctx.status(HttpStatus.NOT_FOUND);
			render(ctx, "Δεν βρέθηκε", Html.message(false, "Δεν υπάρχει ξενοδοχείο με αυτόν τον κωδικό.")
					+ "<p><a href=\"/\">Επιστροφή στην αναζήτηση</a></p>");
			return;
		}
		String base = "/hotels/" + hotel.id();
		String csrf = csrfToken(ctx);

		StringBuilder body = new StringBuilder();
		body.append("<p class=\"back\"><a href=\"/\">← Όλα τα ξενοδοχεία</a></p>\n")
				.append("<h1>").append(esc(hotel.name())).append("</h1>\n")
				.append("<p class=\"sub\">").append(esc(hotel.city())).append(", ").append(esc(hotel.country())).append("</p>\n");

		clientsSection(ctx, hotel, base, body);
		roomBookingsSection(ctx, hotel, base, csrf, body);
		availableRoomsSection(ctx, hotel, base, csrf, body);

		render(ctx, hotel.name(), body.toString());
	}

	// (i) clients of the hotel by last name prefix
	private void clientsSection(Context ctx, Db.Hotel hotel, String base, StringBuilder body) throws SQLException {
		String raw = ctx.queryParam("lname");
		String prefix = param(raw);
		body.append("<section class=\"card\" id=\"pelates\">\n<h2>Πελάτες του ξενοδοχείου</h2>\n")
				.append("<form method=\"get\" action=\"").append(base).append("#pelates\" class=\"row\">\n")
				.append("<label>Αρχικά γράμματα του επωνύμου")
				.append("<input type=\"search\" name=\"lname\" value=\"").append(esc(prefix)).append("\" maxlength=\"100\"></label>\n")
				.append("<button type=\"submit\">Αναζήτηση</button>\n</form>\n");
		if (raw != null) {
			List<Db.Client> clients = db.searchClients(hotel.id(), prefix);
			if (clients.isEmpty()) {
				body.append(Html.message(false, "Δεν βρέθηκαν πελάτες.")).append('\n');
			} else {
				body.append("<p class=\"count\">").append(clients.size()).append(clients.size() == 1 ? " πελάτης" : " πελάτες").append("</p>\n")
						.append("<div class=\"scroll\"><table>\n<thead><tr><th>Κωδικός</th><th>Επώνυμο</th><th>Όνομα</th><th>Φύλο</th>")
						.append("<th>Ημ. γέννησης</th><th>Διεύθυνση</th><th>Πόλη</th><th>Χώρα</th><th>Έγγραφο</th></tr></thead>\n<tbody>\n");
				for (Db.Client c : clients) {
					body.append("<tr><td class=\"num\"><a href=\"").append(base).append("?client=").append(c.id())
							.append("#kratiseis\" title=\"Κρατήσεις του πελάτη\">").append(c.id()).append("</a></td>")
							.append("<td>").append(esc(c.lname())).append("</td>")
							.append("<td>").append(esc(c.fname())).append("</td>")
							.append("<td>").append(esc(c.sex())).append("</td>")
							.append("<td class=\"nowrap\">").append(esc(c.dateOfBirth())).append("</td>")
							.append("<td>").append(esc(c.address())).append("</td>")
							.append("<td>").append(esc(c.city())).append("</td>")
							.append("<td>").append(esc(c.country())).append("</td>")
							.append("<td>").append(esc(c.document())).append("</td></tr>\n");
				}
				body.append("</tbody>\n</table></div>\n");
			}
		}
		body.append("</section>\n");
	}

	// (ii) room bookings of one client in the hotel, each with a form that updates it
	private void roomBookingsSection(Context ctx, Db.Hotel hotel, String base, String csrf, StringBuilder body)
			throws SQLException {
		String raw = ctx.queryParam("client");
		String text = param(raw);
		body.append("<section class=\"card\" id=\"kratiseis\">\n<h2>Κρατήσεις δωματίων πελάτη</h2>\n")
				.append("<form method=\"get\" action=\"").append(base).append("#kratiseis\" class=\"row\">\n")
				.append("<label>Κωδικός πελάτη")
				.append("<input type=\"number\" name=\"client\" value=\"").append(esc(text)).append("\" min=\"0\" step=\"1\" required></label>\n")
				.append("<button type=\"submit\">Εμφάνιση</button>\n</form>\n");
		if (raw != null) {
			Integer clientId = parseInt(text);
			if (clientId == null || clientId < 0) {
				body.append(Html.message(false, "Ο κωδικός πελάτη πρέπει να είναι μη αρνητικός ακέραιος.")).append('\n');
			} else {
				List<Db.RoomBooking> bookings = db.roomBookings(hotel.id(), clientId);
				if (bookings.isEmpty()) {
					body.append(Html.message(false,
							"Δεν υπάρχει πελάτης με αυτόν τον κωδικό που να έχει κρατήσεις δωματίων σε αυτό το ξενοδοχείο.")).append('\n');
				}
				for (Db.RoomBooking b : bookings) {
					body.append("<article class=\"booking\">\n")
							.append("<dl class=\"facts\">")
							.append("<div><dt>Κράτηση</dt><dd>").append(b.hotelBookingId()).append("</dd></div>")
							.append("<div><dt>Δωμάτιο</dt><dd>").append(b.roomId()).append("</dd></div>")
							.append("<div><dt>Άφιξη</dt><dd>").append(esc(b.checkin())).append("</dd></div>")
							.append("<div><dt>Αναχώρηση</dt><dd>").append(esc(b.checkout())).append("</dd></div>")
							.append("<div><dt>Τιμή</dt><dd>").append(esc(b.rate() == null ? "" : b.rate().toPlainString())).append("</dd></div>")
							.append("</dl>\n")
							.append("<form method=\"post\" action=\"").append(base).append("/roombookings/update\" class=\"row\">\n")
							.append(Html.csrfField(csrf))
							.append("<input type=\"hidden\" name=\"booking\" value=\"").append(b.hotelBookingId()).append("\">")
							.append("<input type=\"hidden\" name=\"room\" value=\"").append(b.roomId()).append("\">")
							.append("<input type=\"hidden\" name=\"client\" value=\"").append(clientId).append("\">\n")
							.append("<label>Νέα άφιξη<input type=\"date\" name=\"checkin\" value=\"").append(esc(b.checkin())).append("\" required></label>\n")
							.append("<label>Νέα αναχώρηση<input type=\"date\" name=\"checkout\" value=\"").append(esc(b.checkout())).append("\" required></label>\n")
							.append("<label>Νέα τιμή<input type=\"number\" name=\"rate\" value=\"")
							.append(esc(b.rate() == null ? "" : b.rate().toPlainString())).append("\" min=\"0\" step=\"0.01\" required></label>\n")
							.append("<button type=\"submit\">Ενημέρωση</button>\n</form>\n</article>\n");
				}
			}
		}
		body.append("</section>\n");
	}

	// (iii) rooms of the hotel that are free for a whole period, and a form that books one
	private void availableRoomsSection(Context ctx, Db.Hotel hotel, String base, String csrf, StringBuilder body)
			throws SQLException {
		String rawIn = ctx.queryParam("checkin");
		String rawOut = ctx.queryParam("checkout");
		body.append("<section class=\"card\" id=\"domatia\">\n<h2>Διαθέσιμα δωμάτια και νέα κράτηση</h2>\n")
				.append("<form method=\"get\" action=\"").append(base).append("#domatia\" class=\"row\">\n")
				.append("<label>Άφιξη<input type=\"date\" name=\"checkin\" value=\"").append(esc(param(rawIn))).append("\" required></label>\n")
				.append("<label>Αναχώρηση<input type=\"date\" name=\"checkout\" value=\"").append(esc(param(rawOut))).append("\" required></label>\n")
				.append("<button type=\"submit\">Εμφάνιση</button>\n</form>\n");
		if (rawIn != null || rawOut != null) {
			LocalDate checkin = parseDate(rawIn);
			LocalDate checkout = parseDate(rawOut);
			String problem = periodProblem(checkin, checkout, true);
			if (problem != null) {
				body.append(Html.message(false, problem)).append('\n');
			} else {
				List<Db.Room> rooms = db.availableRooms(hotel.id(), checkin, checkout);
				if (rooms.isEmpty()) {
					body.append(Html.message(false, "Κανένα δωμάτιο δεν είναι ελεύθερο για όλη την περίοδο.")).append('\n');
				} else {
					body.append("<p class=\"count\">").append(rooms.size())
							.append(rooms.size() == 1 ? " ελεύθερο δωμάτιο" : " ελεύθερα δωμάτια")
							.append(" από ").append(esc(checkin)).append(" έως ").append(esc(checkout)).append("</p>\n")
							.append("<form method=\"post\" action=\"").append(base).append("/bookings\" class=\"stack\">\n")
							.append(Html.csrfField(csrf))
							.append("<input type=\"hidden\" name=\"checkin\" value=\"").append(esc(checkin)).append("\">")
							.append("<input type=\"hidden\" name=\"checkout\" value=\"").append(esc(checkout)).append("\">\n")
							.append("<div class=\"scroll rooms\"><table>\n<thead><tr><th>Επιλογή</th><th>Κωδικός</th><th>Αριθμός</th><th>Τύπος</th></tr></thead>\n<tbody>\n");
					for (Db.Room r : rooms) {
						body.append("<tr><td><input type=\"radio\" name=\"room\" value=\"").append(r.id())
								.append("\" id=\"room-").append(r.id()).append("\" required></td>")
								.append("<td class=\"num\"><label for=\"room-").append(r.id()).append("\">").append(r.id()).append("</label></td>")
								.append("<td class=\"num\">").append(r.number()).append("</td>")
								.append("<td>").append(esc(r.type())).append("</td></tr>\n");
					}
					body.append("</tbody>\n</table></div>\n")
							.append("<div class=\"row\">\n<label>Κωδικός πελάτη<input type=\"number\" name=\"client\" min=\"0\" step=\"1\" required></label>\n")
							.append("<button type=\"submit\">Κράτηση</button>\n</div>\n</form>\n");
				}
			}
		}
		body.append("</section>\n");
	}

	/** Returns what is wrong with the period in Greek, or null when it is fine. */
	private static String periodProblem(LocalDate checkin, LocalDate checkout, boolean notInThePast) {
		if (checkin == null || checkout == null) {
			return "Δώστε έγκυρες ημερομηνίες άφιξης και αναχώρησης.";
		}
		if (!checkout.isAfter(checkin)) {
			return "Η αναχώρηση πρέπει να είναι μετά την άφιξη.";
		}
		if (notInThePast && checkin.isBefore(LocalDate.now())) {
			return "Η άφιξη δεν μπορεί να είναι στο παρελθόν.";
		}
		return null;
	}

	private void updateRoomBooking(Context ctx) {
		Integer hotelId = parseInt(ctx.pathParam("id"));
		if (hotelId == null) {
			ctx.redirect("/", HttpStatus.SEE_OTHER);
			return;
		}
		Integer bookingId = parseInt(ctx.formParam("booking"));
		Integer roomId = parseInt(ctx.formParam("room"));
		Integer clientId = parseInt(ctx.formParam("client"));
		LocalDate checkin = parseDate(ctx.formParam("checkin"));
		LocalDate checkout = parseDate(ctx.formParam("checkout"));
		BigDecimal rate = parseAmount(ctx.formParam("rate"));

		Flash flash;
		String problem = periodProblem(checkin, checkout, false);
		if (bookingId == null || roomId == null) {
			flash = new Flash(false, "Δεν δόθηκε έγκυρη κράτηση δωματίου.");
		} else if (problem != null) {
			flash = new Flash(false, problem);
		} else if (rate == null) {
			flash = new Flash(false, "Η τιμή πρέπει να είναι μη αρνητικός αριθμός.");
		} else {
			try {
				int rows = db.updateRoomBooking(hotelId, bookingId, roomId, checkin, checkout, rate);
				flash = rows == 1
						? new Flash(true, "Η κράτηση δωματίου ενημερώθηκε.")
						: new Flash(false, "Δεν ενημερώθηκε τίποτα.");
			} catch (SQLException e) {
				flash = new Flash(false, "Η ενημέρωση απορρίφθηκε: " + firstLine(e.getMessage()));
			}
		}
		ctx.sessionAttribute(SESSION_FLASH, flash);
		String target = "/hotels/" + hotelId + (clientId == null ? "" : "?client=" + clientId) + "#kratiseis";
		ctx.redirect(target, HttpStatus.SEE_OTHER);
	}

	private void createBooking(Context ctx) {
		Integer hotelId = parseInt(ctx.pathParam("id"));
		if (hotelId == null) {
			ctx.redirect("/", HttpStatus.SEE_OTHER);
			return;
		}
		Integer roomId = parseInt(ctx.formParam("room"));
		Integer clientId = parseInt(ctx.formParam("client"));
		LocalDate checkin = parseDate(ctx.formParam("checkin"));
		LocalDate checkout = parseDate(ctx.formParam("checkout"));

		Flash flash;
		String problem = periodProblem(checkin, checkout, true);
		if (problem != null) {
			flash = new Flash(false, problem);
		} else if (roomId == null) {
			flash = new Flash(false, "Επιλέξτε ένα δωμάτιο.");
		} else if (clientId == null || clientId < 0) {
			flash = new Flash(false, "Ο κωδικός πελάτη πρέπει να είναι μη αρνητικός ακέραιος.");
		} else {
			try {
				if (!db.roomBelongsToHotel(hotelId, roomId)) {
					flash = new Flash(false, "Το δωμάτιο δεν ανήκει σε αυτό το ξενοδοχείο.");
				} else {
					OptionalInt created = db.insertBooking(roomId, clientId, checkin, checkout);
					flash = created.isPresent()
							? new Flash(true, "Δημιουργήθηκε η κράτηση " + created.getAsInt() + " για το δωμάτιο " + roomId + ".")
							: new Flash(false, "Δεν υπάρχει πελάτης με κωδικό " + clientId + ".");
				}
			} catch (SQLException e) {
				flash = new Flash(false, "Η κράτηση απορρίφθηκε: " + firstLine(e.getMessage()));
			}
		}
		ctx.sessionAttribute(SESSION_FLASH, flash);
		String target = "/hotels/" + hotelId;
		if (checkin != null && checkout != null) {
			target += "?checkin=" + Html.url(checkin) + "&checkout=" + Html.url(checkout);
		}
		ctx.redirect(target + "#domatia", HttpStatus.SEE_OTHER);
	}

	// ---------------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------------

	private static void render(Context ctx, String title, String body) {
		String user = currentUser(ctx);
		ctx.html(Html.page(title, user, user == null ? null : csrfToken(ctx), takeFlash(ctx), body));
	}

	private static Flash takeFlash(Context ctx) {
		if (ctx.req().getSession(false) == null) {
			return null;
		}
		return ctx.consumeSessionAttribute(SESSION_FLASH);
	}

	private static String param(String value) {
		return value == null ? "" : value.trim();
	}

	private static Integer parseInt(String text) {
		if (text == null) {
			return null;
		}
		try {
			return Integer.valueOf(text.trim());
		} catch (NumberFormatException e) {
			return null;
		}
	}

	private static LocalDate parseDate(String text) {
		if (text == null) {
			return null;
		}
		try {
			return LocalDate.parse(text.trim());
		} catch (DateTimeParseException e) {
			return null;
		}
	}

	/** A non-negative amount of money, or null when the text is not one. */
	private static BigDecimal parseAmount(String text) {
		if (text == null) {
			return null;
		}
		try {
			BigDecimal amount = new BigDecimal(text.trim().replace(',', '.'));
			return amount.signum() < 0 || amount.precision() - amount.scale() > 12 ? null : amount;
		} catch (NumberFormatException e) {
			return null;
		}
	}

	static String firstLine(String message) {
		if (message == null) {
			return "";
		}
		int end = message.indexOf('\n');
		return end < 0 ? message : message.substring(0, end);
	}
}
