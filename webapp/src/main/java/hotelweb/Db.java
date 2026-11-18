package hotelweb;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.OptionalInt;
import java.util.Properties;

/**
 * All the SQL of the application (MySQL). Every method opens its own connection
 * and every user value reaches the database as a PreparedStatement parameter.
 */
public final class Db {

	public record Hotel(int id, String name, String city, String country) {
	}

	public record Client(int id, String lname, String fname, String sex, LocalDate dateOfBirth,
			String address, String city, String country, String document) {
	}

	public record RoomBooking(int hotelBookingId, int roomId, LocalDate checkin, LocalDate checkout, BigDecimal rate) {
	}

	public record Room(int id, int number, String type) {
	}

	private final Config config;

	public Db(Config config) {
		this.config = config;
	}

	private Connection open() throws SQLException {
		Properties props = new Properties();
		if (config.dbUser() != null) {
			props.setProperty("user", config.dbUser());
		}
		if (config.dbPassword() != null) {
			props.setProperty("password", config.dbPassword());
		}
		props.setProperty("characterEncoding", "UTF-8");
		props.setProperty("connectTimeout", "5000");
		return DriverManager.getConnection(config.dbUrl(), props);
	}

	/** Tries to connect until it succeeds or the time runs out (MySQL may still be starting). */
	public void waitUntilReachable(long maxMillis) throws SQLException {
		long deadline = System.currentTimeMillis() + maxMillis;
		while (true) {
			try (Connection conn = open()) {
				return;
			} catch (SQLException e) {
				if (System.currentTimeMillis() >= deadline) {
					throw e;
				}
				try {
					Thread.sleep(2000);
				} catch (InterruptedException interrupted) {
					Thread.currentThread().interrupt();
					throw e;
				}
			}
		}
	}

	private interface Write<T> {
		T run() throws SQLException;
	}

	/**
	 * Runs a write transaction again when MySQL chose it as a deadlock victim (error 1213).
	 * This can happen when a booking of a room is changed at the very moment another booking
	 * of the same room is inserted; MySQL has rolled the transaction back, so repeating it is safe.
	 */
	private static <T> T retryOnDeadlock(Write<T> write) throws SQLException {
		final int attempts = 3;
		for (int attempt = 1;; attempt++) {
			try {
				return write.run();
			} catch (SQLException e) {
				if (e.getErrorCode() != 1213 || attempt == attempts) {
					throw e;
				}
			}
		}
	}

	/** Escapes the LIKE wildcards of a prefix typed by the user (escape character: backslash). */
	static String escapeLike(String prefix) {
		return prefix.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
	}

	// ---------------------------------------------------------------------------------
	// Users of the web application
	// ---------------------------------------------------------------------------------

	public int countUsers() throws SQLException {
		try (Connection conn = open();
				PreparedStatement st = conn.prepareStatement("SELECT COUNT(*) FROM app_user");
				ResultSet res = st.executeQuery()) {
			res.next();
			return res.getInt(1);
		}
	}

	public void insertUser(String username, String passwordHash) throws SQLException {
		try (Connection conn = open();
				PreparedStatement st = conn.prepareStatement(
						"INSERT INTO app_user (username, password_hash) VALUES (?, ?)")) {
			st.setString(1, username);
			st.setString(2, passwordHash);
			st.executeUpdate();
		}
	}

	/** Returns the stored BCrypt hash of the user, or null when there is no such user. */
	public String findPasswordHash(String username) throws SQLException {
		try (Connection conn = open();
				PreparedStatement st = conn.prepareStatement(
						"SELECT password_hash FROM app_user WHERE username = ?")) {
			st.setString(1, username);
			try (ResultSet res = st.executeQuery()) {
				return res.next() ? res.getString(1) : null;
			}
		}
	}

	// ---------------------------------------------------------------------------------
	// Hotels
	// ---------------------------------------------------------------------------------

	public List<Hotel> searchHotels(String prefix) throws SQLException {
		String sql = "SELECT h.idHotel, h.name, h.city, h.country "
				+ "FROM hotel h "
				+ "WHERE LOWER(h.name) LIKE CONCAT(LOWER(?), '%') "
				+ "ORDER BY h.name, h.idHotel";
		List<Hotel> hotels = new ArrayList<>();
		try (Connection conn = open(); PreparedStatement st = conn.prepareStatement(sql)) {
			st.setString(1, escapeLike(prefix));
			try (ResultSet res = st.executeQuery()) {
				while (res.next()) {
					hotels.add(new Hotel(res.getInt("idHotel"), res.getString("name"),
							res.getString("city"), res.getString("country")));
				}
			}
		}
		return hotels;
	}

	public Hotel findHotel(int hotelId) throws SQLException {
		String sql = "SELECT h.idHotel, h.name, h.city, h.country FROM hotel h WHERE h.idHotel = ?";
		try (Connection conn = open(); PreparedStatement st = conn.prepareStatement(sql)) {
			st.setInt(1, hotelId);
			try (ResultSet res = st.executeQuery()) {
				if (!res.next()) {
					return null;
				}
				return new Hotel(res.getInt("idHotel"), res.getString("name"),
						res.getString("city"), res.getString("country"));
			}
		}
	}

	// (i) clients of the hotel by last name prefix, alphabetically
	public List<Client> searchClients(int hotelId, String lastNamePrefix) throws SQLException {
		String sql = "SELECT DISTINCT pe.idPerson, pe.lname, pe.fname, pe.sex, pe.dateofbirth, "
				+ "       pe.address, pe.city, pe.country, cl.documentclient "
				+ "FROM room rm "
				+ "JOIN roombooking rb ON rb.roomID = rm.idRoom "
				+ "JOIN client cl ON cl.idClient = rb.bookedforpersonID "
				+ "JOIN person pe ON pe.idPerson = cl.idClient "
				+ "WHERE rm.idHotel = ? AND LOWER(pe.lname) LIKE CONCAT(LOWER(?), '%') "
				+ "ORDER BY pe.lname, pe.fname, pe.idPerson";
		List<Client> clients = new ArrayList<>();
		try (Connection conn = open(); PreparedStatement st = conn.prepareStatement(sql)) {
			st.setInt(1, hotelId);
			st.setString(2, escapeLike(lastNamePrefix));
			try (ResultSet res = st.executeQuery()) {
				while (res.next()) {
					clients.add(new Client(res.getInt("idPerson"), res.getString("lname"), res.getString("fname"),
							res.getString("sex"), res.getObject("dateofbirth", LocalDate.class),
							res.getString("address"), res.getString("city"), res.getString("country"),
							res.getString("documentclient")));
				}
			}
		}
		return clients;
	}

	// (ii) room bookings of one client in the hotel, ordered by booking id
	public List<RoomBooking> roomBookings(int hotelId, int clientId) throws SQLException {
		String sql = "SELECT rb.hotelbookingID, rb.roomID, rb.checkin, rb.checkout, rb.rate "
				+ "FROM roombooking rb "
				+ "JOIN room rm ON rm.idRoom = rb.roomID "
				+ "JOIN client cl ON cl.idClient = rb.bookedforpersonID "
				+ "WHERE rm.idHotel = ? AND cl.idClient = ? "
				+ "ORDER BY rb.hotelbookingID, rb.roomID";
		List<RoomBooking> bookings = new ArrayList<>();
		try (Connection conn = open(); PreparedStatement st = conn.prepareStatement(sql)) {
			st.setInt(1, hotelId);
			st.setInt(2, clientId);
			try (ResultSet res = st.executeQuery()) {
				while (res.next()) {
					bookings.add(new RoomBooking(res.getInt("hotelbookingID"), res.getInt("roomID"),
							res.getObject("checkin", LocalDate.class), res.getObject("checkout", LocalDate.class),
							res.getBigDecimal("rate")));
				}
			}
		}
		return bookings;
	}

	/**
	 * Updates one room booking of the hotel and returns the number of rows changed.
	 * Returns 0 when the room is not a room of this hotel.
	 *
	 * The UPDATE mentions only roombooking: its triggers lock the row of the room and
	 * modify hotelbooking, so the statement must not read those tables (MySQL error 1442).
	 */
	public int updateRoomBooking(int hotelId, int hotelBookingId, int roomId,
			LocalDate checkin, LocalDate checkout, BigDecimal rate) throws SQLException {
		if (!roomBelongsToHotel(hotelId, roomId)) {
			return 0;
		}
		return retryOnDeadlock(() -> updateRoomBookingOnce(hotelBookingId, roomId, checkin, checkout, rate));
	}

	private int updateRoomBookingOnce(int hotelBookingId, int roomId,
			LocalDate checkin, LocalDate checkout, BigDecimal rate) throws SQLException {
		String sql = "UPDATE roombooking SET checkin = ?, checkout = ?, rate = ? "
				+ "WHERE hotelbookingID = ? AND roomID = ?";
		try (Connection conn = open()) {
			conn.setAutoCommit(false);
			try (PreparedStatement st = conn.prepareStatement(sql)) {
				st.setObject(1, checkin);
				st.setObject(2, checkout);
				st.setBigDecimal(3, rate);
				st.setInt(4, hotelBookingId);
				st.setInt(5, roomId);
				int rows = st.executeUpdate();
				conn.commit();
				return rows;
			} catch (SQLException e) {
				conn.rollback();
				throw e;
			}
		}
	}

	// (iii) rooms of the hotel that are free for a whole period
	public List<Room> availableRooms(int hotelId, LocalDate checkin, LocalDate checkout) throws SQLException {
		// A booking takes the nights from checkin up to, not including, checkout.
		String sql = "SELECT rm.idRoom, rm.`number`, rm.roomtype "
				+ "FROM room rm "
				+ "WHERE rm.idHotel = ? "
				+ "  AND NOT EXISTS (SELECT 1 FROM roombooking rb "
				+ "                  WHERE rb.roomID = rm.idRoom AND rb.checkin < ? AND rb.checkout > ?) "
				+ "ORDER BY rm.`number`, rm.idRoom";
		List<Room> rooms = new ArrayList<>();
		try (Connection conn = open(); PreparedStatement st = conn.prepareStatement(sql)) {
			st.setInt(1, hotelId);
			st.setObject(2, checkout);
			st.setObject(3, checkin);
			try (ResultSet res = st.executeQuery()) {
				while (res.next()) {
					rooms.add(new Room(res.getInt("idRoom"), res.getInt("number"), res.getString("roomtype")));
				}
			}
		}
		return rooms;
	}

	public boolean roomBelongsToHotel(int hotelId, int roomId) throws SQLException {
		String sql = "SELECT 1 FROM room rm WHERE rm.idRoom = ? AND rm.idHotel = ?";
		try (Connection conn = open(); PreparedStatement st = conn.prepareStatement(sql)) {
			st.setInt(1, roomId);
			st.setInt(2, hotelId);
			try (ResultSet res = st.executeQuery()) {
				return res.next();
			}
		}
	}

	/**
	 * Creates a hotel booking with one room booking, in one transaction.
	 * Returns the new booking id, or empty when there is no client with this id.
	 *
	 * The two inserts stay separate, simple statements: the triggers of each table
	 * modify the other one, so a statement must not mention both (MySQL error 1442).
	 */
	public OptionalInt insertBooking(int roomId, int clientId, LocalDate checkin, LocalDate checkout)
			throws SQLException {
		return retryOnDeadlock(() -> insertBookingOnce(roomId, clientId, checkin, checkout));
	}

	private OptionalInt insertBookingOnce(int roomId, int clientId, LocalDate checkin, LocalDate checkout)
			throws SQLException {
		String insertHotelBooking = "INSERT INTO hotelbooking "
				+ "(reservationdate, cancellationdate, bookedbyclientID, payed, status) "
				+ "SELECT CURRENT_DATE, GREATEST(CURRENT_DATE, DATE_SUB(CAST(? AS DATE), INTERVAL 10 DAY)), "
				+ "       cl.idClient, 0, 'confirmed' "
				+ "FROM client cl WHERE cl.idClient = ?";
		String insertRoomBooking = "INSERT INTO roombooking "
				+ "(hotelbookingID, roomID, bookedforpersonID, checkin, checkout) VALUES (?, ?, ?, ?, ?)";
		try (Connection conn = open()) {
			conn.setAutoCommit(false);
			try {
				int hotelBookingId;
				try (PreparedStatement st = conn.prepareStatement(insertHotelBooking, Statement.RETURN_GENERATED_KEYS)) {
					st.setObject(1, checkin);
					st.setInt(2, clientId);
					if (st.executeUpdate() == 0) {
						conn.rollback();
						return OptionalInt.empty();
					}
					try (ResultSet keys = st.getGeneratedKeys()) {
						if (!keys.next()) {
							throw new SQLException("The database did not return the id of the new booking.");
						}
						hotelBookingId = keys.getInt(1);
					}
				}
				try (PreparedStatement st = conn.prepareStatement(insertRoomBooking)) {
					st.setInt(1, hotelBookingId);
					st.setInt(2, roomId);
					st.setInt(3, clientId);
					st.setObject(4, checkin);
					st.setObject(5, checkout);
					st.executeUpdate();
				}
				conn.commit();
				return OptionalInt.of(hotelBookingId);
			} catch (SQLException e) {
				conn.rollback();
				throw e;
			}
		}
	}
}
