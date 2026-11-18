package db_phase_B;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * Console application of phase B: talks to the hotel database over JDBC.
 *
 * Every value typed by the user reaches the database as a parameter of a
 * PreparedStatement, never as part of the SQL text.
 */
public class DbApp {

	private static final String LINE = "-----------------------------------------------------------------------------------------";

	private Connection conn;
	private final StandardInputRead reader = new StandardInputRead();

	// ---------------------------------------------------------------------------------
	// Erotima 1: connection
	// ---------------------------------------------------------------------------------

	/** Connects to the database. The address may be "host" or "host:port" (default port 5432). */
	public boolean connect(String address, String dbName, String username, String password) {
		String hostAndPort = address.contains(":") ? address : address + ":5432";
		try {
			conn = DriverManager.getConnection("jdbc:postgresql://" + hostAndPort + "/" + dbName, username, password);
			conn.setAutoCommit(false);
			System.out.println("Connection successful!");
			return true;
		} catch (SQLException e) {
			System.out.println("Could not connect: " + e.getMessage());
			return false;
		}
	}

	public void dbClose() {
		if (conn == null) {
			return;
		}
		try {
			conn.close();
		} catch (SQLException e) {
			System.out.println("Problem while closing the connection: " + e.getMessage());
		}
	}

	// ---------------------------------------------------------------------------------
	// Erotima 2: search hotels by name prefix, alphabetically, with a running number
	// ---------------------------------------------------------------------------------

	/** Prints the hotels whose name starts with the prefix and returns their ids in the order shown. */
	public List<Integer> searchHotel(String prefix) throws SQLException {
		String sql = "SELECT h.\"idHotel\", h.name, h.city, h.country "
				+ "FROM hotel h "
				+ "WHERE starts_with(lower(h.name), lower(?)) "
				+ "ORDER BY h.name, h.\"idHotel\"";
		List<Integer> hotelIds = new ArrayList<>();
		try (PreparedStatement st = conn.prepareStatement(sql)) {
			st.setString(1, prefix);
			try (ResultSet res = st.executeQuery()) {
				while (res.next()) {
					hotelIds.add(res.getInt("idHotel"));
					System.out.println(hotelIds.size() + ") " + res.getString("name")
							+ " (" + res.getString("city") + ", " + res.getString("country") + ")");
				}
			}
		}
		conn.commit();
		if (hotelIds.isEmpty()) {
			System.out.println("No hotel name starts with \"" + prefix + "\".");
		}
		System.out.println(LINE);
		return hotelIds;
	}

	// upo-erotima (i): clients of the hotel by last name prefix, alphabetically
	public void searchClients(int hotelId, String lastNamePrefix) throws SQLException {
		String sql = "SELECT DISTINCT pe.\"idPerson\", pe.lname, pe.fname, pe.sex, pe.dateofbirth, "
				+ "       pe.address, pe.city, pe.country, cl.documentclient "
				+ "FROM room rm "
				+ "JOIN roombooking rb ON rb.\"roomID\" = rm.\"idRoom\" "
				+ "JOIN client cl ON cl.\"idClient\" = rb.\"bookedforpersonID\" "
				+ "JOIN person pe ON pe.\"idPerson\" = cl.\"idClient\" "
				+ "WHERE rm.\"idHotel\" = ? AND starts_with(lower(pe.lname), lower(?)) "
				+ "ORDER BY pe.lname, pe.fname, pe.\"idPerson\"";
		int count = 0;
		try (PreparedStatement st = conn.prepareStatement(sql)) {
			st.setInt(1, hotelId);
			st.setString(2, lastNamePrefix);
			try (ResultSet res = st.executeQuery()) {
				while (res.next()) {
					count++;
					System.out.println("id: " + res.getInt("idPerson")
							+ "  " + res.getString("lname") + " " + res.getString("fname")
							+ "  sex: " + res.getString("sex")
							+ "  born: " + res.getDate("dateofbirth")
							+ "  address: " + res.getString("address") + ", " + res.getString("city") + ", " + res.getString("country")
							+ "  document: " + res.getString("documentclient"));
				}
			}
		}
		conn.commit();
		System.out.println(count == 0 ? "No clients found." : count + " client(s).");
		System.out.println(LINE);
	}

	// upo-erotima (ii): room bookings of one client in the hotel, ordered by booking id

	/** One room booking, identified by its key (hotelbookingID, roomID). */
	private static class RoomBooking {
		final int hotelBookingId;
		final int roomId;

		RoomBooking(int hotelBookingId, int roomId) {
			this.hotelBookingId = hotelBookingId;
			this.roomId = roomId;
		}
	}

	private List<RoomBooking> displayRoomBookings(int hotelId, int clientId) throws SQLException {
		String sql = "SELECT rb.\"hotelbookingID\", rb.\"roomID\", rb.checkin, rb.checkout, rb.rate "
				+ "FROM roombooking rb "
				+ "JOIN room rm ON rm.\"idRoom\" = rb.\"roomID\" "
				+ "JOIN client cl ON cl.\"idClient\" = rb.\"bookedforpersonID\" "
				+ "WHERE rm.\"idHotel\" = ? AND cl.\"idClient\" = ? "
				+ "ORDER BY rb.\"hotelbookingID\", rb.\"roomID\"";
		List<RoomBooking> bookings = new ArrayList<>();
		try (PreparedStatement st = conn.prepareStatement(sql)) {
			st.setInt(1, hotelId);
			st.setInt(2, clientId);
			try (ResultSet res = st.executeQuery()) {
				while (res.next()) {
					bookings.add(new RoomBooking(res.getInt("hotelbookingID"), res.getInt("roomID")));
					System.out.println(bookings.size() + ") booking: " + res.getInt("hotelbookingID")
							+ "  room: " + res.getInt("roomID")
							+ "  checkin: " + res.getDate("checkin")
							+ "  checkout: " + res.getDate("checkout")
							+ "  rate: " + res.getBigDecimal("rate"));
				}
			}
		}
		conn.commit();
		if (bookings.isEmpty()) {
			System.out.println("There is no client with this id who has room bookings in this hotel.");
		}
		System.out.println(LINE);
		return bookings;
	}

	private void updateRoomBooking(RoomBooking booking, LocalDate checkin, LocalDate checkout, BigDecimal rate)
			throws SQLException {
		String sql = "UPDATE roombooking SET checkin = ?, checkout = ?, rate = ? "
				+ "WHERE \"hotelbookingID\" = ? AND \"roomID\" = ?";
		try (PreparedStatement st = conn.prepareStatement(sql)) {
			st.setObject(1, checkin);
			st.setObject(2, checkout);
			st.setBigDecimal(3, rate);
			st.setInt(4, booking.hotelBookingId);
			st.setInt(5, booking.roomId);
			int rows = st.executeUpdate();
			conn.commit();
			System.out.println(rows == 1 ? "The room booking was updated." : "Nothing was updated.");
		} catch (SQLException e) {
			conn.rollback();
			System.out.println("The update was refused: " + firstLine(e.getMessage()));
		}
	}

	// upo-erotima (iii): rooms of the hotel that are free for a whole period

	/** One free room, as shown in the numbered list. */
	private static class FreeRoom {
		final int roomId;

		FreeRoom(int roomId) {
			this.roomId = roomId;
		}
	}

	private List<FreeRoom> displayAvailableRooms(int hotelId, LocalDate checkin, LocalDate checkout) throws SQLException {
		// A booking takes the nights from checkin up to, not including, checkout.
		String sql = "SELECT rm.\"idRoom\", rm.number, rm.roomtype "
				+ "FROM room rm "
				+ "WHERE rm.\"idHotel\" = ? "
				+ "  AND NOT EXISTS (SELECT 1 FROM roombooking rb "
				+ "                  WHERE rb.\"roomID\" = rm.\"idRoom\" AND rb.checkin < ? AND rb.checkout > ?) "
				+ "ORDER BY rm.number, rm.\"idRoom\"";
		List<FreeRoom> rooms = new ArrayList<>();
		try (PreparedStatement st = conn.prepareStatement(sql)) {
			st.setInt(1, hotelId);
			st.setObject(2, checkout);
			st.setObject(3, checkin);
			try (ResultSet res = st.executeQuery()) {
				while (res.next()) {
					rooms.add(new FreeRoom(res.getInt("idRoom")));
					System.out.println(rooms.size() + ") room id: " + res.getInt("idRoom")
							+ "  number: " + res.getInt("number")
							+ "  type: " + res.getString("roomtype"));
				}
			}
		}
		conn.commit();
		if (rooms.isEmpty()) {
			System.out.println("No room is free for the whole period.");
		}
		System.out.println(LINE);
		return rooms;
	}

	private void insertBooking(int roomId, int clientId, LocalDate checkin, LocalDate checkout) throws SQLException {
		String insertHotelBooking = "INSERT INTO hotelbooking "
				+ "(reservationdate, cancellationdate, \"bookedbyclientID\", payed, status) "
				+ "SELECT current_date, GREATEST(current_date, ?::date - 10), cl.\"idClient\", false, 'confirmed' "
				+ "FROM client cl WHERE cl.\"idClient\" = ? "
				+ "RETURNING idhotelbooking";
		String insertRoomBooking = "INSERT INTO roombooking "
				+ "(\"hotelbookingID\", \"roomID\", \"bookedforpersonID\", checkin, checkout) VALUES (?, ?, ?, ?, ?)";
		try {
			int hotelBookingId;
			try (PreparedStatement st = conn.prepareStatement(insertHotelBooking)) {
				st.setObject(1, checkin);
				st.setInt(2, clientId);
				try (ResultSet res = st.executeQuery()) {
					if (!res.next()) {
						conn.rollback();
						System.out.println("There is no client with id " + clientId + ".");
						return;
					}
					hotelBookingId = res.getInt(1);
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
			System.out.println("Booking " + hotelBookingId + " was created for room " + roomId + ".");
		} catch (SQLException e) {
			conn.rollback();
			System.out.println("The booking was refused: " + firstLine(e.getMessage()));
		}
	}

	// ---------------------------------------------------------------------------------
	// Menus
	// ---------------------------------------------------------------------------------

	private void printMainMenu() {
		System.out.println("=========================================================================================");
		System.out.println("1) Search hotel by name prefix and choose one");
		System.out.println("2) Exit");
		System.out.println("=========================================================================================");
	}

	private void printHotelMenu() {
		System.out.println("1) Search clients of the hotel by last name prefix");
		System.out.println("2) Show the room bookings of a client and update one");
		System.out.println("3) Show available rooms for a period and book one");
		System.out.println("0) Back to the main menu");
	}

	/** Shows the hotel menu until the user goes back. A database error only cancels the current action. */
	private void hotelMenu(int hotelId) {
		while (true) {
			printHotelMenu();
			int choice = reader.readIntInRange("Choose: ", 0, 3);
			if (choice == 0) {
				return;
			}
			try {
				if (hotelAction(hotelId, choice)) {
					return;
				}
			} catch (SQLException e) {
				reportAndRollback(e);
			}
		}
	}

	/** Runs one action of the hotel menu. Returns true when the user asked for the main menu. */
	private boolean hotelAction(int hotelId, int choice) throws SQLException {
		{
			if (choice == 1) {
				String prefix = reader.readString("Client last name prefix: ");
				searchClients(hotelId, prefix);
			} else if (choice == 2) {
				int clientId = reader.readNonNegativeInt("Client id: ");
				List<RoomBooking> bookings = displayRoomBookings(hotelId, clientId);
				if (bookings.isEmpty()) {
					return false;
				}
				int number = reader.readIntInRange("Number of the booking to update (0 to go back to the main menu): ", 0, bookings.size());
				if (number == 0) {
					return true;
				}
				LocalDate checkin = reader.readDate("New checkin (year-month-day): ");
				LocalDate checkout = reader.readDate("New checkout (year-month-day): ");
				if (!checkout.isAfter(checkin)) {
					System.out.println("The checkout must be after the checkin.");
					return false;
				}
				BigDecimal rate = reader.readAmount("New room rate: ");
				updateRoomBooking(bookings.get(number - 1), checkin, checkout, rate);
			} else {
				LocalDate checkin = reader.readDate("Checkin (year-month-day): ");
				LocalDate checkout = reader.readDate("Checkout (year-month-day): ");
				if (!checkout.isAfter(checkin)) {
					System.out.println("The checkout must be after the checkin.");
					return false;
				}
				if (checkin.isBefore(LocalDate.now())) {
					System.out.println("The checkin cannot be in the past.");
					return false;
				}
				List<FreeRoom> rooms = displayAvailableRooms(hotelId, checkin, checkout);
				if (rooms.isEmpty()) {
					return false;
				}
				int number = reader.readIntInRange("Number of the room to book (0 to cancel): ", 0, rooms.size());
				if (number == 0) {
					return false;
				}
				int clientId = reader.readNonNegativeInt("Client id: ");
				insertBooking(rooms.get(number - 1).roomId, clientId, checkin, checkout);
			}
		}
		return false;
	}

	private void reportAndRollback(SQLException e) {
		System.out.println("The database refused the request: " + firstLine(e.getMessage()));
		try {
			conn.rollback();
		} catch (SQLException rollbackError) {
			System.out.println("Problem while cancelling the action: " + firstLine(rollbackError.getMessage()));
		}
	}

	private void mainMenu() {
		while (true) {
			printMainMenu();
			int choice = reader.readIntInRange("Choose: ", 1, 2);
			if (choice == 2) {
				return;
			}
			String prefix = reader.readString("Hotel name prefix: ");
			List<Integer> hotelIds;
			try {
				hotelIds = searchHotel(prefix);
			} catch (SQLException e) {
				reportAndRollback(e);
				continue;
			}
			if (hotelIds.isEmpty()) {
				continue;
			}
			int number = reader.readIntInRange("Number of the hotel (0 to go back): ", 0, hotelIds.size());
			if (number != 0) {
				hotelMenu(hotelIds.get(number - 1));
			}
		}
	}

	private static String firstLine(String message) {
		if (message == null) {
			return "";
		}
		int end = message.indexOf('\n');
		return end < 0 ? message : message.substring(0, end);
	}

	public static void main(String[] args) {
		DbApp dbapp = new DbApp();
		System.out.println("----------------------------------Welcome!-----------------------------------------------");
		try {
			String address = dbapp.reader.readString("Database address (IP or IP:port): ");
			String dbName = dbapp.reader.readString("Database name: ");
			String username = dbapp.reader.readString("Username: ");
			String password = dbapp.reader.readPassword("Password: ");
			if (!dbapp.connect(address, dbName, username, password)) {
				return;
			}
			dbapp.mainMenu();
		} catch (StandardInputRead.EndOfInputException e) {
			System.out.println();
		} finally {
			dbapp.dbClose();
			System.out.println("----------------------Thanks for using our system!------------------------------");
		}
	}
}
