import mysql.connector

# CONFIGURATION: Update this password to match your MySQL installation!
db_config = {
    'user': 'root',
    'password': '123456',  # <--- CHANGE THIS to your actual MySQL root password
    'host': 'localhost'
}

try:
    # 1. Connect to MySQL Server
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor()

    # 2. Create Database
    cursor.execute("CREATE DATABASE IF NOT EXISTS ambulance_db")
    print("✅ Database 'ambulance_db' check/creation successful.")

    # 3. Connect to the new Database
    conn.database = 'ambulance_db'

    # 4. Create Users Table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            email VARCHAR(100) NOT NULL UNIQUE,
            password VARCHAR(255) NOT NULL,
            role ENUM('driver', 'dispatcher') NOT NULL
        )
    """)
    print("✅ Table 'users' created.")

    # 7. Create Bookings Table (NEW)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS bookings (
            id INT AUTO_INCREMENT PRIMARY KEY,
            patient_name VARCHAR(100),
            location VARCHAR(255) NOT NULL,
            emergency_type VARCHAR(50) NOT NULL,
            notes TEXT,
            status ENUM('Pending', 'Assigned', 'Completed') DEFAULT 'Pending',
            driver_id INT DEFAULT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    print("✅ Table 'bookings' created.")

    # 5. Insert a Test User (if not exists)
    cursor.execute("SELECT * FROM users WHERE email = 'driver@test.com'")
    if not cursor.fetchone():
        cursor.execute("INSERT INTO users (email, password, role) VALUES ('driver@test.com', '123456', 'driver')")
        conn.commit()
        print("✅ Test user (driver@test.com / 123456) added.")
    else:
        print("ℹ️ Test user already exists.")

    # 6. Insert a Test Dispatcher (NEW)
    cursor.execute("SELECT * FROM users WHERE email = 'admin@test.com'")
    if not cursor.fetchone():
        cursor.execute("INSERT INTO users (email, password, role) VALUES ('admin@test.com', 'admin123', 'dispatcher')")
        conn.commit()
        print("✅ Test Dispatcher (admin@test.com / admin123) added.")
    else:
        print("ℹ️ Test Dispatcher already exists.")


    cursor.close()
    conn.close()
    print("\n🎉 SETUP COMPLETE! You can now run app.py")

except mysql.connector.Error as err:
    print(f"❌ Error: {err}")
    print("HINT: Did you update the 'password' in this script to match your MySQL installation?")