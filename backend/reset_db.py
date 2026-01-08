import mysql.connector

# Database Configuration
db_config = {
    'user': 'root',
    'password': '123456',  # Make sure this matches your password
    'host': 'localhost',
    'database': 'ambulance_db'
}

try:
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor()

    # 1. Delete all bookings
    print("🧹 Clearing all bookings...")
    cursor.execute("DELETE FROM bookings")

    # 2. Reset the ID counter to 1 (so the next booking is #1, not #15)
    cursor.execute("ALTER TABLE bookings AUTO_INCREMENT = 1")
    
    conn.commit()
    print("✅ SUCCESS: Database is clean! Bookings deleted.")

except Exception as e:
    print(f"❌ Error: {e}")

finally:
    if 'conn' in locals() and conn.is_connected():
        cursor.close()
        conn.close()