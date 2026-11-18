package hotelweb;

/** Settings of the application. They come only from environment variables. */
public record Config(String dbUrl, String dbUser, String dbPassword,
		String adminUser, String adminPassword, int port) {

	public static Config fromEnv() {
		String dbUrl = env("DB_URL");
		if (dbUrl == null) {
			throw new IllegalStateException("The environment variable DB_URL is not set.");
		}
		int port = 8080;
		String portText = env("PORT");
		if (portText != null) {
			try {
				port = Integer.parseInt(portText);
			} catch (NumberFormatException e) {
				throw new IllegalStateException("The environment variable PORT is not a number.");
			}
		}
		return new Config(dbUrl, env("DB_USER"), env("DB_PASSWORD"),
				env("APP_ADMIN_USER"), env("APP_ADMIN_PASSWORD"), port);
	}

	private static String env(String name) {
		String value = System.getenv(name);
		return value == null || value.isBlank() ? null : value.trim();
	}

	/** Never print the passwords, e.g. by logging the record. */
	@Override
	public String toString() {
		return "Config[dbUrl=" + dbUrl + ", dbUser=" + dbUser + ", port=" + port + "]";
	}
}
