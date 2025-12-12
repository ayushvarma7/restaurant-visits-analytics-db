# createDB.PractI.VarmaA.R
# CS5200 Practicum I - Database Creation Script
# Author: Ayush Varma
# Semester: Fall 2025

library(RMySQL)
library(RSQLite)
library(DBI)

# Clear environment
rm(list = ls())

# ==================== DATABASE CONNECTIONS ====================

source("db_config.R")

mydb <- dbConnect(
  RMySQL::MySQL(),
  user = db_user,
  password = db_password,
  dbname = db_name,
  host = db_host,
  port = db_port
)

print("Connected to MySQL database")

sqlite_db <- dbConnect(SQLite(), "restaurants-db.sqlitedb")
print("Connected to SQLite database")



# ==================== CREATE TABLES ====================

# 1. Restaurants (using rid from SQLite db)
create_restaurants <- "
CREATE TABLE IF NOT EXISTS Restaurants (
    RestaurantID INT PRIMARY KEY,
    RestaurantName VARCHAR(100) NOT NULL UNIQUE,
    City VARCHAR(100),
    State VARCHAR(50),
    HasService BOOLEAN DEFAULT TRUE,
    INDEX idx_restaurant_name (RestaurantName),
    INDEX idx_state (State)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
"
dbSendQuery(mydb, create_restaurants)
print("Created Restaurants table")

# 2. Servers 
create_servers <- "
CREATE TABLE IF NOT EXISTS Servers (
    ServerEmpID INT PRIMARY KEY,
    ServerName VARCHAR(100) NOT NULL,
    ServerBirthDate DATE,
    ServerTIN VARCHAR(20),
    INDEX idx_server_name (ServerName)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 
"
dbSendQuery(mydb, create_servers)
print("Created Servers table")

# 3. ServerEmployments (junction table)
create_server_employments <- "
CREATE TABLE IF NOT EXISTS ServerEmployments (
    ServerEmpID INT,
    RestaurantID INT,
    StartDateHired DATE,
    EndDateHired DATE,
    HourlyRate DECIMAL(5,2) DEFAULT 0.00,
    PRIMARY KEY (ServerEmpID, RestaurantID, StartDateHired),
    FOREIGN KEY (ServerEmpID) REFERENCES Servers(ServerEmpID)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (RestaurantID) REFERENCES Restaurants(RestaurantID)
        ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_server (ServerEmpID),
    INDEX idx_restaurant (RestaurantID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 
"
dbSendQuery(mydb, create_server_employments)
print("Created ServerEmployments junction table")

# 4. Customers
create_customers <- "
CREATE TABLE IF NOT EXISTS Customers (
    CustomerID INT AUTO_INCREMENT PRIMARY KEY,
    CustomerName VARCHAR(100),
    CustomerPhone VARCHAR(30),
    CustomerEmail VARCHAR(150),
    LoyaltyMember BOOLEAN DEFAULT FALSE,
    DateAdded TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_email (CustomerEmail),
    INDEX idx_loyalty (LoyaltyMember),
    INDEX idx_email (CustomerEmail)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 
"
dbSendQuery(mydb, create_customers)
print("Created Customers table")

# 5. MealTypes (lookup table)
create_meal_types <- "
CREATE TABLE IF NOT EXISTS MealTypes (
    MealTypeID INT AUTO_INCREMENT PRIMARY KEY,
    MealTypeName VARCHAR(20) NOT NULL UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 
"
dbSendQuery(mydb, create_meal_types)
print("Created MealTypes lookup table")

# 6. PaymentMethods (lookup table)
create_payment_methods <- "
CREATE TABLE IF NOT EXISTS PaymentMethods (
    PaymentMethodID INT AUTO_INCREMENT PRIMARY KEY,
    MethodName VARCHAR(30) NOT NULL UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 
"
dbSendQuery(mydb, create_payment_methods)
print("Created PaymentMethods lookup table")

# 7. Visits 
create_visits <- "
CREATE TABLE IF NOT EXISTS Visits (
    VisitID INT AUTO_INCREMENT PRIMARY KEY,
    RestaurantID INT NOT NULL,
    CustomerID INT,
    ServerEmpID INT,
    VisitDate DATE NOT NULL,
    VisitTime TIME,
    MealTypeID INT,
    PartySize INT DEFAULT 2,
    Genders VARCHAR(50),
    WaitTime INT DEFAULT 0,
    FoodBill DECIMAL(10,2) DEFAULT 0.00,
    AlcoholBill DECIMAL(10,2) DEFAULT 0.00,
    TipAmount DECIMAL(10,2) DEFAULT 0.00,
    DiscountApplied DECIMAL(5,2) DEFAULT 0.00,
    PaymentMethodID INT,
    OrderedAlcohol BOOLEAN DEFAULT FALSE,
    
    FOREIGN KEY (RestaurantID) REFERENCES Restaurants(RestaurantID),
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID),
    FOREIGN KEY (ServerEmpID) REFERENCES Servers(ServerEmpID),
    FOREIGN KEY (MealTypeID) REFERENCES MealTypes(MealTypeID),
    FOREIGN KEY (PaymentMethodID) REFERENCES PaymentMethods(PaymentMethodID),
    
    INDEX idx_visit_date (VisitDate),
    INDEX idx_restaurant (RestaurantID),
    INDEX idx_composite (RestaurantID, VisitDate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 
"
dbSendQuery(mydb, create_visits)
print("Created Visits table")

# ==================== POPULATE LOOKUP TABLES ====================

# Insert MealTypes
dbSendQuery(mydb, "INSERT INTO MealTypes (MealTypeName) VALUES 
    ('Breakfast'), ('Lunch'), ('Dinner'), ('Take-Out')")
print("Populated MealTypes lookup table")

# Insert PaymentMethods
dbSendQuery(mydb, "INSERT INTO PaymentMethods (MethodName) VALUES 
    ('Cash'), ('Credit Card'), ('Mobile Payment')")
print("Populated PaymentMethods lookup table")

# ==================== VERIFY TABLE CREATION ====================

print("========== Verification ==========")

tables <- dbListTables(mydb)
print("Tables created in MySQL:")
print(tables)

for (table in tables) {
  count_query <- paste("SELECT COUNT(*) as count FROM", table)
  result <- dbGetQuery(mydb, count_query)
  print(paste(table, "has", result$count, "rows"))
}

# Verify lookup tables
meal_types <- dbGetQuery(mydb, "SELECT * FROM MealTypes")
print("MealTypes:")
print(meal_types)

payment_methods <- dbGetQuery(mydb, "SELECT * FROM PaymentMethods")
print("PaymentMethods:")
print(payment_methods)

restaurants <- dbGetQuery(mydb, "SELECT * FROM Restaurants ORDER BY RestaurantID")
print("Restaurants (first 5):")
print(head(restaurants, 5))

# ==================== CLEANUP ====================

dbDisconnect(mydb)
dbDisconnect(sqlite_db)

print("========================================")
print("Database creation completed successfully!")
print("7 tables created with lookup data loaded")
print("========================================")