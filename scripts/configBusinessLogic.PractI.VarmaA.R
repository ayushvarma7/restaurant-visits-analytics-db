# configBusinessLogic.PractI.VarmaA.R
# CS5200 Practicum I - Business Logic Configuration Script
# Author: Ayush Varma
# Semester: Fall 2025
# Purpose: Create and test stored procedures for visit management

library(RMySQL)
library(DBI)

# Clear environment
rm(list = ls())

# ==================== DATABASE CONNECTION ====================

source("db_config.R")

# Function to create a new connection
connect_to_db <- function() {
  dbConnect(
    RMySQL::MySQL(),
    user = db_user,
    password = db_password,
    dbname = db_name,
    host = db_host,
    port = db_port
  )
}

# Initial connection
mydb <- connect_to_db()
print("Connected to MySQL database")

# ==================== PART 1: CREATE storeVisit PROCEDURE ====================
# This procedure assumes all foreign keys exist

print("========================================")
print("Creating storeVisit Stored Procedure")
print("========================================")

# Drop existing procedure if it exists
tryCatch({
  dbExecute(mydb, "DROP PROCEDURE IF EXISTS storeVisit")
  print("Dropped existing storeVisit procedure")
}, error = function(e) {
  print(paste("Note:", e$message))
})

# Create storeVisit procedure
storeVisit_sql <- "
CREATE PROCEDURE storeVisit(
    IN p_RestaurantID INT,
    IN p_CustomerID INT,
    IN p_ServerEmpID INT,
    IN p_VisitDate DATE,
    IN p_VisitTime TIME,
    IN p_MealTypeID INT,
    IN p_PartySize INT,
    IN p_Genders VARCHAR(50),
    IN p_WaitTime INT,
    IN p_FoodBill DECIMAL(10,2),
    IN p_AlcoholBill DECIMAL(10,2),
    IN p_TipAmount DECIMAL(10,2),
    IN p_DiscountApplied DECIMAL(10,2),
    IN p_PaymentMethodID INT,
    IN p_OrderedAlcohol BOOLEAN
)
BEGIN
    -- Declare variables for validation
    DECLARE restaurant_exists INT DEFAULT 0;
    DECLARE customer_exists INT DEFAULT 0;
    DECLARE server_exists INT DEFAULT 0;
    
    -- Validate that restaurant exists
    SELECT COUNT(*) INTO restaurant_exists 
    FROM Restaurants 
    WHERE RestaurantID = p_RestaurantID;
    
    IF restaurant_exists = 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error: Restaurant ID does not exist';
    END IF;
    
    -- Validate that customer exists (if not NULL)
    IF p_CustomerID IS NOT NULL THEN
        SELECT COUNT(*) INTO customer_exists 
        FROM Customers 
        WHERE CustomerID = p_CustomerID;
        
        IF customer_exists = 0 THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Error: Customer ID does not exist';
        END IF;
    END IF;
    
    -- Validate that server exists (if not NULL)
    IF p_ServerEmpID IS NOT NULL THEN
        SELECT COUNT(*) INTO server_exists 
        FROM Servers 
        WHERE ServerEmpID = p_ServerEmpID;
        
        IF server_exists = 0 THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Error: Server Employee ID does not exist';
        END IF;
    END IF;
    
    -- Insert the visit
    INSERT INTO Visits (
        RestaurantID, CustomerID, ServerEmpID, VisitDate, VisitTime,
        MealTypeID, PartySize, Genders, WaitTime, FoodBill, AlcoholBill,
        TipAmount, DiscountApplied, PaymentMethodID, OrderedAlcohol
    ) VALUES (
        p_RestaurantID, p_CustomerID, p_ServerEmpID, p_VisitDate, p_VisitTime,
        p_MealTypeID, p_PartySize, p_Genders, p_WaitTime, p_FoodBill, p_AlcoholBill,
        p_TipAmount, p_DiscountApplied, p_PaymentMethodID, p_OrderedAlcohol
    );
    
    -- Return the new Visit ID
    SELECT LAST_INSERT_ID() AS NewVisitID;
END
"

# Execute procedure creation
tryCatch({
  dbExecute(mydb, storeVisit_sql)
  print("Successfully created storeVisit procedure")
}, error = function(e) {
  print(paste("Error creating storeVisit:", e$message))
})

# ==================== PART 2: CREATE storeNewVisit PROCEDURE ====================
# This procedure handles cases where foreign keys might not exist

print("========================================")
print("Creating storeNewVisit Stored Procedure")
print("========================================")

# Drop existing procedure if it exists
tryCatch({
  dbExecute(mydb, "DROP PROCEDURE IF EXISTS storeNewVisit")
  print("Dropped existing storeNewVisit procedure")
}, error = function(e) {
  print(paste("Note:", e$message))
})

# Create storeNewVisit procedure
storeNewVisit_sql <- "
CREATE PROCEDURE storeNewVisit(
    -- Restaurant parameters
    IN p_RestaurantName VARCHAR(100),
    IN p_RestaurantCity VARCHAR(50),
    IN p_RestaurantState VARCHAR(50),
    IN p_HasService BOOLEAN,
    -- Customer parameters
    IN p_CustomerName VARCHAR(100),
    IN p_CustomerPhone VARCHAR(15),
    IN p_CustomerEmail VARCHAR(100),
    IN p_LoyaltyMember BOOLEAN,
    -- Server parameters
    IN p_ServerEmpID INT,
    IN p_ServerName VARCHAR(100),
    IN p_ServerBirthDate DATE,
    IN p_ServerTIN VARCHAR(11),
    IN p_HourlyRate DECIMAL(5,2),
    -- Visit parameters
    IN p_VisitDate DATE,
    IN p_VisitTime TIME,
    IN p_MealTypeID INT,
    IN p_PartySize INT,
    IN p_Genders VARCHAR(50),
    IN p_WaitTime INT,
    IN p_FoodBill DECIMAL(10,2),
    IN p_AlcoholBill DECIMAL(10,2),
    IN p_TipAmount DECIMAL(10,2),
    IN p_DiscountApplied DECIMAL(10,2),
    IN p_PaymentMethodID INT,
    IN p_OrderedAlcohol BOOLEAN
)
BEGIN
    -- Declare variables
    DECLARE v_RestaurantID INT;
    DECLARE v_CustomerID INT DEFAULT NULL;
    DECLARE v_ServerID INT DEFAULT NULL;
    DECLARE v_NewVisitID INT;
    
    -- Handle Restaurant
    IF p_RestaurantName IS NOT NULL THEN
        -- Check if restaurant exists by name and city
        SELECT RestaurantID INTO v_RestaurantID
        FROM Restaurants
        WHERE RestaurantName = p_RestaurantName 
        AND City = p_RestaurantCity
        LIMIT 1;
        
        -- If restaurant doesn't exist, create it
        IF v_RestaurantID IS NULL THEN
            -- Get next available RestaurantID
            SELECT IFNULL(MAX(RestaurantID), 0) + 1 INTO v_RestaurantID
            FROM Restaurants;
            
            INSERT INTO Restaurants (RestaurantID, RestaurantName, City, State, HasService)
            VALUES (v_RestaurantID, p_RestaurantName, p_RestaurantCity, 
                   p_RestaurantState, IFNULL(p_HasService, 1));
        END IF;
    END IF;
    
    -- Handle Customer (if email provided)
    IF p_CustomerEmail IS NOT NULL AND p_CustomerEmail != '' THEN
        -- Check if customer exists by email
        SELECT CustomerID INTO v_CustomerID
        FROM Customers
        WHERE CustomerEmail = p_CustomerEmail
        LIMIT 1;
        
        -- If customer doesn't exist, create it
        IF v_CustomerID IS NULL THEN
            INSERT INTO Customers (CustomerName, CustomerPhone, CustomerEmail, LoyaltyMember)
            VALUES (p_CustomerName, p_CustomerPhone, p_CustomerEmail, 
                   IFNULL(p_LoyaltyMember, 0));
            
            SET v_CustomerID = LAST_INSERT_ID();
        END IF;
    END IF;
    
    -- Handle Server (if ServerEmpID provided)
    IF p_ServerEmpID IS NOT NULL THEN
        -- Check if server exists
        SELECT ServerEmpID INTO v_ServerID
        FROM Servers
        WHERE ServerEmpID = p_ServerEmpID
        LIMIT 1;
        
        -- If server doesn't exist, create it
        IF v_ServerID IS NULL AND p_ServerName IS NOT NULL THEN
            INSERT INTO Servers (ServerEmpID, ServerName, ServerBirthDate, ServerTIN)
            VALUES (p_ServerEmpID, p_ServerName, p_ServerBirthDate, 
                   IFNULL(p_ServerTIN, ''));
            
            SET v_ServerID = p_ServerEmpID;
            
            -- Also create employment record if server was created
            IF v_RestaurantID IS NOT NULL THEN
                INSERT INTO ServerEmployments (ServerEmpID, RestaurantID, 
                                             StartDateHired, HourlyRate)
                VALUES (v_ServerID, v_RestaurantID, p_VisitDate, 
                       IFNULL(p_HourlyRate, 15.00))
                ON DUPLICATE KEY UPDATE HourlyRate = IFNULL(p_HourlyRate, HourlyRate);
            END IF;
        ELSE
            SET v_ServerID = p_ServerEmpID;
        END IF;
    END IF;
    
    -- Insert the visit
    INSERT INTO Visits (
        RestaurantID, CustomerID, ServerEmpID, VisitDate, VisitTime,
        MealTypeID, PartySize, Genders, WaitTime, FoodBill, AlcoholBill,
        TipAmount, DiscountApplied, PaymentMethodID, OrderedAlcohol
    ) VALUES (
        v_RestaurantID, v_CustomerID, v_ServerID, p_VisitDate, p_VisitTime,
        IFNULL(p_MealTypeID, 2), -- Default to Lunch
        IFNULL(p_PartySize, 2),  -- Default party size
        IFNULL(p_Genders, ''), 
        IFNULL(p_WaitTime, 0), 
        IFNULL(p_FoodBill, 0), 
        IFNULL(p_AlcoholBill, 0),
        IFNULL(p_TipAmount, 0), 
        IFNULL(p_DiscountApplied, 0), 
        IFNULL(p_PaymentMethodID, 1), -- Default to Cash
        IFNULL(p_OrderedAlcohol, 0)
    );
    
    SET v_NewVisitID = LAST_INSERT_ID();
    
    -- Return summary of what was created
    SELECT 
        v_NewVisitID AS NewVisitID,
        v_RestaurantID AS RestaurantID,
        v_CustomerID AS CustomerID,
        v_ServerID AS ServerID,
        CASE WHEN v_RestaurantID IS NOT NULL THEN 'Created/Found' ELSE 'Not Created' END AS RestaurantStatus,
        CASE WHEN v_CustomerID IS NOT NULL THEN 'Created/Found' ELSE 'Not Created' END AS CustomerStatus,
        CASE WHEN v_ServerID IS NOT NULL THEN 'Created/Found' ELSE 'Not Created' END AS ServerStatus;
END
"

# Execute procedure creation
tryCatch({
  dbExecute(mydb, storeNewVisit_sql)
  print("Successfully created storeNewVisit procedure")
}, error = function(e) {
  print(paste("Error creating storeNewVisit:", e$message))
})

# ==================== PART 3: TEST storeVisit PROCEDURE ====================

print("\n========================================")
print("Testing storeVisit Procedure")
print("========================================")

# Get sample existing IDs for testing
test_data <- dbGetQuery(mydb, "
  SELECT 
    (SELECT RestaurantID FROM Restaurants LIMIT 1) as RestaurantID,
    (SELECT CustomerID FROM Customers LIMIT 1) as CustomerID,
    (SELECT ServerEmpID FROM Servers LIMIT 1) as ServerID
")

print("Using existing IDs for test:")
print(paste("  Restaurant ID:", test_data$RestaurantID))
print(paste("  Customer ID:", test_data$CustomerID))
print(paste("  Server ID:", test_data$ServerID))

# Test storeVisit with existing IDs
test_visit_sql <- sprintf("
  CALL storeVisit(
    %d,                    -- RestaurantID
    %d,                    -- CustomerID  
    %d,                    -- ServerEmpID
    '%s',                  -- VisitDate
    '18:30:00',           -- VisitTime
    3,                    -- MealTypeID (Dinner)
    4,                    -- PartySize
    'MMFF',               -- Genders
    15,                   -- WaitTime
    85.50,                -- FoodBill
    32.00,                -- AlcoholBill
    23.50,                -- TipAmount
    0.00,                 -- DiscountApplied
    2,                    -- PaymentMethodID (Credit Card)
    1                     -- OrderedAlcohol (Yes)
  )",
                          test_data$RestaurantID,
                          test_data$CustomerID,
                          test_data$ServerID,
                          Sys.Date()
)

# Reconnecting before test to ensure clean state since I was getting some unused result error
dbDisconnect(mydb)
mydb <- connect_to_db()

tryCatch({
  result <- dbGetQuery(mydb, test_visit_sql)
  print("SUCCESS: storeVisit executed successfully!")
  print(paste("  New Visit ID created:", result$NewVisitID))
}, error = function(e) {
  print(paste("Error testing storeVisit:", e$message))
})

# Test error handling - invalid RestaurantID
print("\nTesting error handling with invalid RestaurantID:")

# Reconnect to clear any pending results
dbDisconnect(mydb)
mydb <- connect_to_db()

error_test_sql <- "
  CALL storeVisit(
    9999,                 -- Invalid RestaurantID
    NULL,                 -- CustomerID (NULL is allowed)
    NULL,                 -- ServerEmpID (NULL is allowed)
    CURDATE(),           -- VisitDate
    '12:00:00',          -- VisitTime
    2,                   -- MealTypeID
    2,                   -- PartySize
    'MF',                -- Genders
    5,                   -- WaitTime
    25.00,               -- FoodBill
    0.00,                -- AlcoholBill
    5.00,                -- TipAmount
    0.00,                -- DiscountApplied
    1,                   -- PaymentMethodID
    0                    -- OrderedAlcohol
  )"

tryCatch({
  dbExecute(mydb, error_test_sql)
  print("  Unexpected: Should have failed with invalid RestaurantID")
}, error = function(e) {
  print("SUCCESS: Error handling works correctly!")
  print(paste("  Expected error received:", e$message))
})

# ==================== PART 4: TEST storeNewVisit PROCEDURE ====================

print("\n========================================")
print("Testing storeNewVisit Procedure")
print("========================================")

# Reconnect for clean state
dbDisconnect(mydb)
mydb <- connect_to_db()

# Test with all new entities
test_new_visit_sql <- sprintf("
  CALL storeNewVisit(
    -- Restaurant parameters
    'Test Restaurant %s',     -- RestaurantName
    'Boston',                  -- RestaurantCity
    'MA',                      -- RestaurantState
    1,                         -- HasService
    -- Customer parameters
    'Test Customer',           -- CustomerName
    '555-0123',               -- CustomerPhone
    'test%s@example.com',     -- CustomerEmail (unique)
    1,                         -- LoyaltyMember
    -- Server parameters
    %d,                        -- ServerEmpID (unique)
    'Test Server',             -- ServerName
    '1990-01-15',             -- ServerBirthDate
    '123-45-6789',            -- ServerTIN
    18.50,                     -- HourlyRate
    -- Visit parameters
    '%s',                      -- VisitDate
    '19:00:00',               -- VisitTime
    3,                         -- MealTypeID (Dinner)
    6,                         -- PartySize
    'MMMFFF',                 -- Genders
    20,                        -- WaitTime
    125.75,                    -- FoodBill
    48.50,                     -- AlcoholBill
    34.85,                     -- TipAmount
    10.00,                     -- DiscountApplied
    2,                         -- PaymentMethodID
    1                          -- OrderedAlcohol
  )",
                              format(Sys.time(), "%H%M%S"),  # Unique restaurant name
                              format(Sys.time(), "%H%M%S"),  # Unique email
                              as.integer(format(Sys.time(), "%H%M%S")), # Unique ServerEmpID
                              Sys.Date()
)

tryCatch({
  result <- dbGetQuery(mydb, test_new_visit_sql)
  print("SUCCESS: storeNewVisit executed successfully!")
  print("  Results:")
  print(paste("    New Visit ID:", result$NewVisitID))
  print(paste("    Restaurant:", result$RestaurantStatus, "(ID:", result$RestaurantID, ")"))
  print(paste("    Customer:", result$CustomerStatus, "(ID:", result$CustomerID, ")"))
  print(paste("    Server:", result$ServerStatus, "(ID:", result$ServerID, ")"))
}, error = function(e) {
  print(paste("Error testing storeNewVisit:", e$message))
})

# Test with existing entities 
print("\nTesting storeNewVisit with existing entities:")

# Reconnect for clean state
dbDisconnect(mydb)
mydb <- connect_to_db()

# Get an existing restaurant
existing_rest <- dbGetQuery(mydb, 
                            "SELECT RestaurantName, City, State FROM Restaurants LIMIT 1"
)

test_existing_sql <- sprintf("
  CALL storeNewVisit(
    -- Use existing restaurant
    '%s',                      -- RestaurantName (existing)
    '%s',                      -- RestaurantCity (existing)
    '%s',                      -- RestaurantState (existing)
    1,                         -- HasService
    -- New customer
    'Another Test Customer',   -- CustomerName
    '555-9999',               -- CustomerPhone
    'another%s@example.com',  -- CustomerEmail (unique)
    0,                         -- LoyaltyMember
    -- Server parameters (NULL to skip)
    NULL,                      -- ServerEmpID
    NULL,                      -- ServerName
    NULL,                      -- ServerBirthDate
    NULL,                      -- ServerTIN
    NULL,                      -- HourlyRate
    -- Visit parameters
    '%s',                      -- VisitDate
    '12:30:00',               -- VisitTime
    2,                         -- MealTypeID (Lunch)
    2,                         -- PartySize
    'MF',                      -- Genders
    10,                        -- WaitTime
    45.00,                     -- FoodBill
    0.00,                      -- AlcoholBill
    9.00,                      -- TipAmount
    0.00,                      -- DiscountApplied
    1,                         -- PaymentMethodID (Cash)
    0                          -- OrderedAlcohol
  )",
                             existing_rest$RestaurantName,
                             existing_rest$City,
                             existing_rest$State,
                             format(Sys.time(), "%H%M%S"),  # Unique email
                             Sys.Date()
)

tryCatch({
  result <- dbGetQuery(mydb, test_existing_sql)
  print("SUCCESS: storeNewVisit with existing restaurant executed successfully!")
  print("  Results:")
  print(paste("    New Visit ID:", result$NewVisitID))
  print(paste("    Restaurant:", result$RestaurantStatus, "(reused existing)"))
  print(paste("    Customer:", result$CustomerStatus, "(created new)"))
  print(paste("    Server:", result$ServerStatus, "(none provided)"))
}, error = function(e) {
  print(paste("Error:", e$message))
})

# ==================== VERIFICATION & SUMMARY ====================

dbDisconnect(mydb)
mydb <- connect_to_db()

print("\n========================================")
print("Verification & Summary")
print("========================================")

# Final count of visits
final_count <- dbGetQuery(mydb, "SELECT COUNT(*) as count FROM Visits")
print(paste("Total visits in database after tests:", final_count$count))

# ==================== CLEANUP ====================

dbDisconnect(mydb)
print("\nDisconnected from database")
print("========================================")
print("Business logic configuration completed successfully!")
print("All stored procedures created and tested!")
print("========================================")