package db_phase_B;

import java.sql.*;

public class DbApp {

	Connection conn;
	
	//Erotima 1:
	//create connection:
	public void connect(String IP, String dbName, String username, String password) {
		try {
			Class.forName("org.postgresql.Driver"); //as shown at lab
			//getConnection accepts 1 or 3 arguments, so:
			conn  = DriverManager.getConnection("jdbc:postgresql://"+IP+":5432/"+dbName, username, password);
			System.out.println("Connection successful! conn:"+conn); //print
			conn.setAutoCommit(false);
			} catch (Exception e) {
				e.printStackTrace();
				}
		}
	
	public void dbClose() {
		try {
			conn.close();
		} catch (SQLException e) {
			e.printStackTrace();
		}
	}
	
	
	//Erotima 2:
	public void searchHotel(String prefix, int codeClient) {
		try {
			Statement st = conn.createStatement();
			ResultSet res = st.executeQuery("SELECT ROW_NUMBER() OVER(ORDER BY name ASC)::int AS hotelnum, name\r\n"
					+ "FROM hotel\r\n"
					+ "WHERE name LIKE '"+prefix+"%'");//the '"+prefix+"%' represents any letter (A,B,C...)
			//print lines:
			while (res.next()) {
				System.out.println(res.getString("hotelnum")+")"+" "+"hotelname:"+res.getString("name"));
				//System.out.println("Hotel number:"+res.getInt(1)+" name:"+res.getInt(2));
				System.out.println("-----------------------------------------------------");
			}

		//close:
		res.close();
		} catch (SQLException e) {
			e.printStackTrace();
		}
	
	}
	
	//upo-erotima (i):
	public void searchClients(int a, String Cprefix) {
		try {
			Statement st = conn.createStatement();
			ResultSet clients = st.executeQuery("WITH help1 AS (\r\n"
					+ "    SELECT ROW_NUMBER() OVER(ORDER BY name ASC)::int AS hotelnum, ho.\"idHotel\", ho.\"name\", rm.\"idRoom\"\r\n"
					+ "    FROM hotel ho\r\n"
					+ "    INNER JOIN room rm ON (ho.\"idHotel\"=rm.\"idHotel\")\r\n"
					+ "    ), help2 AS (\r\n"
					+ "        SELECT *\r\n"
					+ "        FROM help1\r\n"
					+ "        LEFT JOIN roombooking rb ON (help1.\"idRoom\"=rb.\"roomID\")\r\n"
					+ "    ), help3 AS (\r\n"
					+ "        SELECT *\r\n"
					+ "        FROM help2\r\n"
					+ "        INNER JOIN client cl ON (help2.\"bookedforpersonID\"=cl.\"idClient\")\r\n"
					+ "    ), help4 AS (\r\n"
					+ "        SELECT *\r\n"
					+ "        FROM help3\r\n"
					+ "        INNER JOIN person pe ON (help3.\"idClient\"=pe.\"idPerson\")\r\n"
					+ "    )\r\n"
					+ "\r\n"
					+ "    SELECT ROW_NUMBER() OVER(ORDER BY help4.\"lname\" ASC)::int AS clientnum, help4.\"idClient\",\r\n"
					+ "        help4.\"lname\", help4.\"fname\", help4.\"sex\", help4.\"dateofbirth\", help4.\"address\", help4.\"country\"\r\n"
					+ "    FROM help4\r\n"
					+ "    WHERE help4.\"hotelnum\"="+a+" AND help4.\"lname\" LIKE '"+Cprefix+"%'");//the '"+Cprefix+"%' represents any letter (A,B,C...)
		//print lines:
		while (clients.next()) {
			System.out.println(clients.getString("clientnum")+")" +"id:"+clients.getString("idClient")+" "+"LastName:"+clients.getString("lname")+" " +"FirstName:"+clients.getString("fname")+" " +"sex:"+clients.getString("sex")+" " +"dateofbirth"+clients.getString("dateofbirth")+" " +"address:"+clients.getString("address")+" " +"country:"+clients.getString("country"));
			System.out.println("--------------------------------------------------------------------------------------------------------------------------");
			}
			//close:
			clients.close();
			} catch (SQLException e) {
				e.printStackTrace();
				}
		}
	//upo-erotima (ii):
	public void displayRoomBookings(int b, int i) {
		try {
			Statement st = conn.createStatement();
			ResultSet roomres = st.executeQuery("WITH help1 AS (\r\n"
					+ "    SELECT ROW_NUMBER() OVER(ORDER BY name ASC)::int AS hotelnum, ho.\"idHotel\", ho.\"name\", rm.\"idRoom\", rm.\"roomtype\"\r\n"
					+ "    FROM hotel ho\r\n"
					+ "    INNER JOIN room rm ON (ho.\"idHotel\"=rm.\"idHotel\")\r\n"
					+ "    ), help2 AS (\r\n"
					+ "        SELECT *\r\n"
					+ "        FROM help1\r\n"
					+ "        LEFT JOIN roombooking rb ON (help1.\"idRoom\"=rb.\"roomID\")\r\n"
					+ "    ), help3 AS (\r\n"
					+ "        SELECT *\r\n"
					+ "        FROM help2\r\n"
					+ "        INNER JOIN client cl ON (help2.\"bookedforpersonID\"=cl.\"idClient\")\r\n"
					+ "    ), help4 AS (\r\n"
					+ "        SELECT *\r\n"
					+ "        FROM help3\r\n"
					+ "        INNER JOIN person pe ON (help3.\"idClient\"=pe.\"idPerson\")\r\n"
					+ "    )\r\n"
					+ "\r\n"
					+ "    SELECT ROW_NUMBER() OVER(ORDER BY help4.\"hotelbookingID\" ASC)::int AS bookingnum, help4.\"roomID\",\r\n"
					+ "        help4.\"checkin\", help4.\"checkout\", help4.\"rate\", help4.\"roomtype\"\r\n"
					+ "    FROM help4\r\n"
					+ "    WHERE help4.\"idClient\"="+b+" AND help4.\"hotelnum\"="+i+"");
			//print lines:
			while (roomres.next()) {
				System.out.println("bookingnum:"+roomres.getString("bookingnum")+" "+"roomID:"+roomres.getString("roomID")+" "+"checkin:"+roomres.getString("checkin")
				+"checkout:"+roomres.getString("checkout")+" "+"rate:"+roomres.getString("rate")+" "+"roomtype:"+roomres.getString("roomtype"));
				System.out.println("----------------------------------------------------------------------------------------------------------------------------------");
				}
			//close:
			roomres.close();
		} catch (SQLException e) {
			e.printStackTrace();
		}
	}
	
	public void updateFields(int k, java.util.Date a1, java.util.Date a2, int a3) {
		try {
			Statement st = conn.createStatement();
			ResultSet res =  st.executeQuery("UPDATE roombooking SET checkin="+a1+", checkout="+a2+", rate="+a3+""
					+ "WHERE roombooking.\"hotelbookingID\"="+k+"");
			while (res.next()) {
				System.out.println("checkin:"+res.getString(1)+ "checkout:"+ res.getString(2)+ "rate"+ res.getString(3));
				System.out.println("------------------------------------------------------------------------------------------------------------------------------------");
			}
		} catch (SQLException e) {
			e.printStackTrace();
		}
	}
	
	
	//upo-erotima (iii):
	
	
	//Display main menu:
	public void printMenu() {
		System.out.println("----------------------------------Welcome!-----------------------------------------------");
		System.out.println("=========================================================================================");
		System.out.println("-----------------------------First you need to connect to database-----------------------");
		System.out.println("-----------------------------After connecting to database, you can:----------------------");
		System.out.println("1) Search Hotel via starting letter(insert hotel number).................................");
		System.out.println("Give hotel number and search Client via starting letter(insert client number)............");
		System.out.println("At the same hotel, display Roombooking details for client(insert client number)..........");
		System.out.println("Update roombooking details(insert roombookingRow, checkin, checkout, cost)...............");
		System.out.println("At the same hotel, display available rooms(insert roomRow, roomId, roomtype).............");
		System.out.println("2) Exit..................................................................................");
		System.out.println("=======================================================================================\n");
	}
	
	//Finally create our main function:
	public static void main(String[] args) {

		DbApp dbapp = new DbApp();
		
		StandardInputRead reader = new StandardInputRead();
		
		//print main menu:
		dbapp.printMenu();
		
		//connect to database:
		String ip, dbName, username, pass;
		ip=reader.readString("Please enter database's ip: \n");
		dbName=reader.readString("Please enter database's name: \n");
		username=reader.readString("Please enter username: \n");
		pass=reader.readString("Please enter password: \n");
		//Now we are ready to connect:
		dbapp.connect(ip, dbName, username, pass);
		reader.readString("Press enter to continue..\n");
		
		int userInput=0;
		//get option:
		userInput=reader.readPositiveInt("Would you like to continue? Type 1 for Yes or any other number for No.\n");
		//begin:
		while(userInput==1) {
			//check option if valid:
			if(userInput==1) {
				String hotName, cName, var2=null;
				java.util.Date var3;
				java.util.Date var4;
				int var1=0, var5=0, hotNumInput, id=0, rbNum=0, roomBookingNum=0;
				
				//search hotels:
				hotName = reader.readString("Enter hotel name prefix(A or B or C...):\n");
				dbapp.searchHotel(hotName, var1);
				reader.readString("Press enter to continue..\n");
				
				//search hotel's clients:
				hotNumInput = reader.readPositiveInt("Choose which hotel num you wish to search for details:\n");
				cName = reader.readString("Enter client name prefix(A or B or C...):\n");
				dbapp.searchClients(hotNumInput, cName);
				reader.readString("Press enter to continue..\n");
				
				//display roombooking details for client:
				var1 = reader.readPositiveInt("Enter client's id to display his bookings:\n");
				roomBookingNum = reader.readPositiveInt("Give number of client row:\n");
				dbapp.displayRoomBookings(id, roomBookingNum);
				var2 = reader.readString("Do you wish to update roombookings?\n");
				if (var2=="y" || var2=="Y" || var2=="yes" || var2!="Yes" || var2!="YES") {
					rbNum=reader.readPositiveInt("Enter roombooking rowNum you want to update:\n");
					//need to declare variables, in order to make updates..
					var3 = reader.readDate("Give date for checkin(year-month-day):\n");
					var4 = reader.readDate("Give date for checkout(year-month-day):\n");
					var5 = reader.readPositiveInt("Give amount for room cost:\n");
					dbapp.updateFields(rbNum, var3, var4, var5);
					}
				else {
					continue;
					}
				
				}
			else {
				System.out.println("----------------------Thanks for using our system!------------------------------\n");
				}
			}
		dbapp.dbClose();
		}
}