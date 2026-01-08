CREATE DATABASE ambulance_db;
USE ambulance_db;

CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(100) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    role ENUM('driver', 'dispatcher') NOT NULL
);

-- Insert a test driver (Password is 'password123' without hashing for this simple test)
INSERT INTO users (email, password, role) VALUES ('driver@test.com', 'password123', 'driver');