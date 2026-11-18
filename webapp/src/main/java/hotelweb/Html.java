package hotelweb;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/** Tiny HTML helper. Every dynamic value must pass through {@link #esc(Object)}. */
public final class Html {

	/** A one-time message shown on the next page. */
	public record Flash(boolean ok, String message) {
	}

	private Html() {
	}

	/** Escapes a value for use in HTML text or inside a quoted attribute. Null becomes the empty string. */
	public static String esc(Object value) {
		if (value == null) {
			return "";
		}
		String text = value.toString();
		StringBuilder out = new StringBuilder(text.length() + 16);
		for (int i = 0; i < text.length(); i++) {
			char c = text.charAt(i);
			switch (c) {
				case '&' -> out.append("&amp;");
				case '<' -> out.append("&lt;");
				case '>' -> out.append("&gt;");
				case '"' -> out.append("&quot;");
				case '\'' -> out.append("&#39;");
				default -> out.append(c);
			}
		}
		return out.toString();
	}

	/** Encodes a value for use in a URL query string. */
	public static String url(Object value) {
		return URLEncoder.encode(value == null ? "" : value.toString(), StandardCharsets.UTF_8);
	}

	public static String csrfField(String csrfToken) {
		return "<input type=\"hidden\" name=\"_csrf\" value=\"" + esc(csrfToken) + "\">";
	}

	public static String message(boolean ok, String text) {
		return "<p class=\"msg " + (ok ? "ok" : "err") + "\" role=\"" + (ok ? "status" : "alert") + "\">"
				+ esc(text) + "</p>";
	}

	/**
	 * A whole page. The body is trusted HTML built by the caller; the other values are escaped here.
	 * The username is null on the login page (no navigation bar then).
	 */
	public static String page(String title, String username, String csrfToken, Flash flash, String body) {
		StringBuilder out = new StringBuilder(body.length() + 1024);
		out.append("<!DOCTYPE html>\n<html lang=\"el\">\n<head>\n")
				.append("<meta charset=\"utf-8\">\n")
				.append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n")
				.append("<meta name=\"color-scheme\" content=\"light dark\">\n")
				.append("<title>").append(esc(title)).append(" · Ξενοδοχεία</title>\n")
				.append("<link rel=\"stylesheet\" href=\"/static/style.css\">\n")
				.append("</head>\n<body>\n");
		if (username != null) {
			out.append("<header class=\"top\">\n")
					.append("<a class=\"brand\" href=\"/\">Ξενοδοχεία</a>\n")
					.append("<form method=\"post\" action=\"/logout\" class=\"logout\">")
					.append(csrfField(csrfToken))
					.append("<span class=\"who\">").append(esc(username)).append("</span>")
					.append("<button type=\"submit\" class=\"quiet\">Αποσύνδεση</button></form>\n")
					.append("</header>\n");
		}
		out.append("<main>\n");
		if (flash != null) {
			out.append(message(flash.ok(), flash.message())).append('\n');
		}
		out.append(body).append("\n</main>\n</body>\n</html>\n");
		return out.toString();
	}
}
