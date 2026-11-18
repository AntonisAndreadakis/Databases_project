package db_phase_B;

import java.io.BufferedReader;
import java.io.Console;
import java.io.IOException;
import java.io.InputStreamReader;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;

/**
 * Reads values from the keyboard, asking again until the input is valid.
 *
 * The source of the class used in the 2021 submission was lost (only the compiled
 * .class survived), so this is a rewrite with the methods DbApp needs.
 */
public class StandardInputRead {

	private final BufferedReader in = new BufferedReader(new InputStreamReader(System.in));

	/** Prints the message and returns the line typed, trimmed. */
	public String readString(String message) {
		System.out.print(message);
		System.out.flush();
		try {
			String line = in.readLine();
			if (line == null) {
				throw new EndOfInputException();
			}
			return line.trim();
		} catch (IOException e) {
			throw new EndOfInputException();
		}
	}

	/** Reads a password without showing it when a real console is available. */
	public String readPassword(String message) {
		Console console = System.console();
		if (console != null) {
			char[] typed = console.readPassword("%s", message);
			if (typed == null) {
				throw new EndOfInputException();
			}
			return new String(typed);
		}
		return readString(message);
	}

	/** Reads an integer that is zero or greater. */
	public int readNonNegativeInt(String message) {
		while (true) {
			String text = readString(message);
			try {
				int value = Integer.parseInt(text);
				if (value >= 0) {
					return value;
				}
			} catch (NumberFormatException e) {
				// fall through to the message below
			}
			System.out.println("Please type a whole number, zero or greater.");
		}
	}

	/** Reads an integer between min and max (inclusive). */
	public int readIntInRange(String message, int min, int max) {
		while (true) {
			int value = readNonNegativeInt(message);
			if (value >= min && value <= max) {
				return value;
			}
			System.out.println("Please type a number from " + min + " to " + max + ".");
		}
	}

	/** Reads a date written as year-month-day, for example 2021-06-30. */
	public LocalDate readDate(String message) {
		while (true) {
			String text = readString(message);
			try {
				return LocalDate.parse(text);
			} catch (DateTimeParseException e) {
				System.out.println("Please type the date as year-month-day, for example 2021-06-30.");
			}
		}
	}

	/** Reads an amount of money that is zero or greater, for example 85.50. */
	public BigDecimal readAmount(String message) {
		while (true) {
			String text = readString(message).replace(',', '.');
			try {
				BigDecimal value = new BigDecimal(text);
				if (value.signum() >= 0) {
					return value;
				}
			} catch (NumberFormatException e) {
				// fall through to the message below
			}
			System.out.println("Please type an amount, zero or greater, for example 85.50.");
		}
	}

	/** Thrown when the input ends (Ctrl+Z / Ctrl+D or a closed pipe). */
	public static class EndOfInputException extends RuntimeException {
		private static final long serialVersionUID = 1L;

		public EndOfInputException() {
			super("End of input");
		}
	}
}
