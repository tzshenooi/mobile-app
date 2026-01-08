import mysql.connector

db_config = {
    'user': 'root',
    'password': '123456',  # Check your password
    'host': 'localhost',
    'database': 'ambulance_db'
}

try:
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor()

    # Change the status column to accept ANY text (removes the strict restrictions)
    print(" 1. Updating table schema...")
    cursor.execute("ALTER TABLE bookings MODIFY COLUMN status VARCHAR(50) DEFAULT 'Pending'")
    conn.commit()
    
    print("✅ SUCCESS: Database now accepts 'En Route'!")

except Exception as e:
    print(f"❌ Error: {e}")

finally:
    if 'conn' in locals() and conn.is_connected():
        cursor.close()
        conn.close()