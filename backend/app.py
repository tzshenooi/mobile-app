from flask_cors import CORS
from flask import Flask, request, jsonify
from flask_cors import CORS
import mysql.connector

app = Flask(__name__)
CORS(app) # Allows the Flutter app to talk to this server

# Connect to MySQL (Update with your specific password)
db_config = {
    'user': 'root',
    'password': '123456', 
    'host': 'localhost',
    'database': 'ambulance_db',
}

@app.route('/login', methods=['POST'])
def login():
    data = request.json
    email = data.get('email')
    password = data.get('password')

    try:
        # Check database for user
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)
        
        # WARNING: In production, always use password hashing (e.g., bcrypt)!
        query = "SELECT * FROM users WHERE email = %s AND password = %s"
        cursor.execute(query, (email, password))
        user = cursor.fetchone()
        
        cursor.close()
        conn.close()

        if user:
            return jsonify({
                "status": "success", 
                "message": "Login successful",
                "role": user['role']
            }), 200
        else:
            return jsonify({"status": "fail", "message": "Invalid email or password"}), 401

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/create_booking', methods=['POST'])
def create_booking():
    data = request.json
    patient_name = data.get('patient_name')
    location = data.get('location')
    emergency_type = data.get('emergency_type')
    notes = data.get('notes')

    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        
        query = """
            INSERT INTO bookings (patient_name, location, emergency_type, notes, status)
            VALUES (%s, %s, %s, %s, 'Pending')
        """
        cursor.execute(query, (patient_name, location, emergency_type, notes))
        conn.commit()
        
        booking_id = cursor.lastrowid # Get the ID of the new booking
        cursor.close()
        conn.close()

        return jsonify({"status": "success", "message": "Booking created", "id": booking_id}), 201

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route('/bookings', methods=['GET'])
def get_bookings():
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True) # dictionary=True makes data easier to read
        
        # Get all bookings, newest first
        query = "SELECT * FROM bookings ORDER BY created_at DESC"
        cursor.execute(query)
        bookings = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return jsonify({"status": "success", "data": bookings}), 200

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/assign_booking', methods=['POST'])
def assign_booking():
    data = request.json
    booking_id = data.get('booking_id')
    driver_id = data.get('driver_id')

    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        
        # Update the booking status and assign the driver
        query = "UPDATE bookings SET driver_id = %s, status = 'Assigned' WHERE id = %s"
        cursor.execute(query, (driver_id, booking_id))
        conn.commit()
        
        cursor.close()
        conn.close()

        return jsonify({"status": "success", "message": "Driver assigned successfully"}), 200

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/driver_bookings/<int:driver_id>', methods=['GET'])
def get_driver_bookings(driver_id):
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)
        
        # Fetch only jobs assigned to this specific driver
        query = "SELECT * FROM bookings WHERE driver_id = %s AND status = 'Assigned'"
        cursor.execute(query, (driver_id,))
        bookings = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return jsonify({"status": "success", "data": bookings}), 200

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/update_status', methods=['POST'])
def update_status():
    data = request.json
    booking_id = data.get('booking_id')
    new_status = data.get('status') # 'En Route', 'On Scene', 'Completed'

    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        
        query = "UPDATE bookings SET status = %s WHERE id = %s"
        cursor.execute(query, (new_status, booking_id))
        conn.commit()
        
        cursor.close()
        conn.close()

        return jsonify({"status": "success", "message": "Status updated"}), 200

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500
        
              
if __name__ == '__main__':
    # Host 0.0.0.0 makes it accessible on the network
    app.run(host='0.0.0.0', port=5000, debug=True)