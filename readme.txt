==============================================================================
PROJECT: Smart App for Ambulance Driver (FYP)
==============================================================================

SYSTEM OVERVIEW
---------------
This project is a hybrid ambulance management system consisting of three parts:
1. Backend: Python Flask API + MySQL Database
2. Web Dashboard: React.js (For Dispatchers to create bookings)
3. Mobile App: Flutter (For Drivers to receive tasks)

------------------------------------------------------------------------------
1. PREREQUISITES
------------------------------------------------------------------------------
Ensure you have the following installed on your machine:
- Python (3.x)
- Node.js (Latest LTS)
- Flutter SDK
- MySQL Server (8.0)

------------------------------------------------------------------------------
2. DATABASE SETUP (MySQL)
------------------------------------------------------------------------------
1. Ensure MySQL Server is running (Service: MySQL80).
2. The system uses a Python script to automatically create the database and tables.
3. Open a terminal in the 'backend' folder and run:
   
   cd backend
   python setup_db.py

   > This will create the 'ambulance_db' database and the following tables:
     - users (Stores drivers and dispatchers)
     - bookings (Stores emergency incidents)
   > It also creates default test users.

------------------------------------------------------------------------------
3. BACKEND SERVER SETUP (Python Flask)
------------------------------------------------------------------------------
The backend connects the database to the web and mobile apps.

1. Navigate to the backend folder:
   cd backend

2. Install required libraries (if not done already):
   pip install flask mysql-connector-python flask-cors

3. Start the server:
   python app.py

   > Server will run at: http://localhost:5000
   > Keep this terminal OPEN while running the apps.

------------------------------------------------------------------------------
4. DISPATCHER DASHBOARD SETUP (React.js)
------------------------------------------------------------------------------
The web dashboard is for Dispatchers to view the map and create bookings.

1. Open a NEW terminal and navigate to the dashboard folder:
   cd dispatcher-dashboard

2. Install dependencies (first time only):
   npm install

3. Start the web dashboard:
   npm start

   > The dashboard will open at: http://localhost:3000

------------------------------------------------------------------------------
5. DRIVER MOBILE APP SETUP (Flutter)
------------------------------------------------------------------------------
The mobile app is for Drivers to log in and receive assignments.

1. Open VS Code in the root 'flutter_application_1' folder.
2. Check 'lib/modules/auth/login_screen.dart' to ensure the IP address matches
   your PC's Wi-Fi IP (e.g., http://192.168.x.x:5000/login).
3. Run the app on an Emulator or Physical Device:
   flutter run

------------------------------------------------------------------------------
6. DEFAULT LOGIN CREDENTIALS
------------------------------------------------------------------------------
Use these accounts to test the system:

A. Dispatcher (Web Dashboard)
   - Email:    admin@test.com
   - Password: admin123

B. Ambulance Driver (Mobile App)
   - Email:    driver@test.com
   - Password: 123456

==============================================================================
TROUBLESHOOTING
==============================================================================
- Error: "Connection Refused (10061)"
  - Solution: Make sure MySQL Server is running in Windows Services.

- Error: "CORS Policy" in Web Dashboard
  - Solution: Ensure 'flask-cors' is installed and your backend is running.

- Error: "Connection Error" in Mobile App
  - Solution: Update the API URL in login_screen.dart to your PC's real IP address,
    and ensure your firewall allows Python connections.