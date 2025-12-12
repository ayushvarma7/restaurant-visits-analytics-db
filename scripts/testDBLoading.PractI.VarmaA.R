# testDBLoading.PractI.VarmaA.R
# CS5200 Practicum I - Database Loading Test Script
# Author: Ayush Varma
# Semester: Fall 2025
# Purpose: Verify data integrity between source CSV and loaded database

library(RMySQL)
library(DBI)
library(RSQLite)

# Clear environment
rm(list = ls())

# ==================== DATABASE CONNECTION ====================

source("db_config.R")

# Connect to MySQL database
mydb <- dbConnect(
  RMySQL::MySQL(),
  user = db_user,
  password = db_password,
  dbname = db_name,
  host = db_host,
  port = db_port
)

print("Connected to MySQL database")

# ==================== LOAD SOURCE DATA ====================

# Load CSV data
# csv_file <- "restaurant-visits-200.csv"
csv_file <- "restaurant-visits-179719.csv"
df.orig <- read.csv(csv_file, stringsAsFactors = FALSE, na.strings = c("", "NA"))
print(paste("Loaded", nrow(df.orig), "rows from CSV"))

# Load SQLite data for restaurant count
sqlite_db <- dbConnect(RSQLite::SQLite(), "restaurants-db.sqlitedb")
sqlite_restaurants <- dbGetQuery(sqlite_db, "SELECT COUNT(DISTINCT rid) as count FROM restaurants")
dbDisconnect(sqlite_db)

# ==================== TEST FUNCTIONS ====================

run_test <- function(test_name, csv_value, db_value, tolerance = 0.01) {
  passed <- FALSE
  
  if (is.numeric(csv_value) && is.numeric(db_value)) {
    # For numeric comparisons, use tolerance
    difference <- abs(csv_value - db_value)
    passed <- difference <= tolerance
    
    if (passed) {
      cat(sprintf("PASS: %s\n", test_name))
      cat(sprintf("  CSV: %.2f | DB: %.2f | Difference: %.2f\n", 
                  csv_value, db_value, difference))
    } else {
      cat(sprintf(" FAIL: %s\n", test_name))
      cat(sprintf("  CSV: %.2f | DB: %.2f | Difference: %.2f\n", 
                  csv_value, db_value, difference))
    }
  } else {
    # For count comparisons
    passed <- csv_value == db_value
    
    if (passed) {
      cat(sprintf("PASS: %s\n", test_name))
      cat(sprintf("  CSV: %d | DB: %d | Match: EXACT\n", csv_value, db_value))
    } else {
      cat(sprintf(" FAIL: %s\n", test_name))
      cat(sprintf("  CSV: %d | DB: %d | Difference: %d\n", 
                  csv_value, db_value, abs(csv_value - db_value)))
    }
  }
  
  cat("\n")
  return(passed)
}

# ==================== TEST 1: RESTAURANT COUNT ====================

print("========================================")
print("TEST 1: RESTAURANT COUNT VERIFICATION")
print("========================================")

# Count unique restaurants in CSV
csv_restaurants <- length(unique(df.orig$Restaurant[!is.na(df.orig$Restaurant)]))

# Count restaurants in database
db_restaurants <- dbGetQuery(mydb, "SELECT COUNT(*) as count FROM Restaurants")$count

# Also check against SQLite source
total_expected_restaurants <- sqlite_restaurants$count

test1_result <- run_test(
  "Restaurant Count (CSV unique vs DB)",
  csv_restaurants,
  db_restaurants
)

#We already know that we have one extra restaurant in csv which is not used in db
# Additional check against SQLite
cat(sprintf("  Note: SQLite source had %d restaurants\n", total_expected_restaurants))
cat(sprintf("  Database should have at least %d restaurants (CSV + SQLite)\n\n", 
            csv_restaurants))

# ==================== TEST 2: CUSTOMER COUNT ====================

print("========================================")
print("TEST 2: CUSTOMER COUNT VERIFICATION")
print("========================================")

# Count unique customers in CSV (by email)
csv_customers <- df.orig[!is.na(df.orig$CustomerEmail) & df.orig$CustomerEmail != "", ]
csv_customer_count <- length(unique(csv_customers$CustomerEmail))

# Count customers in database
db_customer_count <- dbGetQuery(mydb, "SELECT COUNT(*) as count FROM Customers")$count

test2_result <- run_test(
  "Customer Count",
  csv_customer_count,
  db_customer_count
)

# ==================== TEST 3: SERVER COUNT ====================

print("========================================")
print("TEST 3: SERVER COUNT VERIFICATION")
print("========================================")

# Count unique servers in CSV (excluding N/A)
valid_servers <- df.orig[!is.na(df.orig$ServerEmpID) & 
                           df.orig$ServerEmpID != "" & 
                           df.orig$ServerName != "N/A", ]
csv_server_count <- length(unique(valid_servers$ServerEmpID))

# Count servers in database
db_server_count <- dbGetQuery(mydb, "SELECT COUNT(*) as count FROM Servers")$count

test3_result <- run_test(
  "Server Count",
  csv_server_count,
  db_server_count
)

# ==================== TEST 4: VISIT COUNT ====================

print("========================================")
print("TEST 4: VISIT COUNT VERIFICATION")
print("========================================")

# Count total visits in CSV
csv_visit_count <- nrow(df.orig)

# Count visits in database
db_visit_count <- dbGetQuery(mydb, "SELECT COUNT(*) as count FROM Visits")$count

test4_result <- run_test(
  "Visit Count",
  csv_visit_count,
  db_visit_count
)

# ==================== TEST 5: FOOD BILL TOTAL ====================

print("========================================")
print("TEST 5: FOOD BILL TOTAL VERIFICATION")
print("========================================")

# Sum food bills in CSV
csv_food_total <- sum(df.orig$FoodBill, na.rm = TRUE)

# Sum food bills in database
db_food_total <- dbGetQuery(mydb, "SELECT SUM(FoodBill) as total FROM Visits")$total

test5_result <- run_test(
  "Food Bill Total",
  csv_food_total,
  db_food_total
)

# ==================== TEST 6: ALCOHOL BILL TOTAL ====================

print("========================================")
print("TEST 6: ALCOHOL BILL TOTAL VERIFICATION")
print("========================================")

# Sum alcohol bills in CSV
csv_alcohol_total <- sum(df.orig$AlcoholBill, na.rm = TRUE)

# Sum alcohol bills in database
db_alcohol_total <- dbGetQuery(mydb, "SELECT SUM(AlcoholBill) as total FROM Visits")$total

test6_result <- run_test(
  "Alcohol Bill Total",
  csv_alcohol_total,
  db_alcohol_total
)

# ==================== TEST 7: TIP TOTAL ====================

print("========================================")
print("TEST 7: TIP AMOUNT TOTAL VERIFICATION")
print("========================================")

# Sum tips in CSV
csv_tip_total <- sum(df.orig$TipAmount, na.rm = TRUE)

# Sum tips in database
db_tip_total <- dbGetQuery(mydb, "SELECT SUM(TipAmount) as total FROM Visits")$total

test7_result <- run_test(
  "Tip Amount Total",
  csv_tip_total,
  db_tip_total
)

# ==================== TEST 8: GRAND TOTAL VERIFICATION ====================

print("========================================")
print("TEST 8: GRAND TOTAL VERIFICATION")
print("========================================")

# Calculate grand total in CSV
csv_grand_total <- csv_food_total + csv_alcohol_total + csv_tip_total

# Calculate grand total in database
db_grand_total <- dbGetQuery(mydb, 
                             "SELECT SUM(FoodBill + AlcoholBill + TipAmount) as total FROM Visits")$total

test8_result <- run_test(
  "Grand Total (Food + Alcohol + Tips)",
  csv_grand_total,
  db_grand_total
)

# ==================== ADDITIONAL INTEGRITY CHECKS ====================

print("========================================")
print("ADDITIONAL DATA INTEGRITY CHECKS")
print("========================================")

# Check for NULL CustomerIDs in visits
null_customers <- dbGetQuery(mydb, 
                             "SELECT COUNT(*) as count FROM Visits WHERE CustomerID IS NULL")$count
cat(sprintf("Visits without customers: %d\n", null_customers))

# Check for NULL ServerEmpIDs in visits
null_servers <- dbGetQuery(mydb, 
                           "SELECT COUNT(*) as count FROM Visits WHERE ServerEmpID IS NULL")$count
cat(sprintf("Visits without servers: %d\n", null_servers))

# Check employment records
employment_count <- dbGetQuery(mydb, 
                               "SELECT COUNT(*) as count FROM ServerEmployments")$count
cat(sprintf("Server employment records: %d\n", employment_count))

# Check average values
avg_party_size_csv <- mean(df.orig$PartySize[df.orig$PartySize != 99], na.rm = TRUE)
avg_party_size_db <- dbGetQuery(mydb, 
                                "SELECT AVG(PartySize) as avg FROM Visits")$avg
cat(sprintf("\nAverage party size - CSV: %.2f | DB: %.2f\n", 
            avg_party_size_csv, avg_party_size_db))

avg_wait_csv <- mean(df.orig$WaitTime, na.rm = TRUE)
avg_wait_db <- dbGetQuery(mydb, 
                          "SELECT AVG(WaitTime) as avg FROM Visits")$avg
cat(sprintf("Average wait time - CSV: %.2f | DB: %.2f\n", 
            avg_wait_csv, avg_wait_db))

# ==================== SUMMARY REPORT ====================

print("\n========================================")
print("TEST SUMMARY REPORT")
print("========================================")

# Collect all test results
test_results <- c(test1_result, test2_result, test3_result, test4_result,
                  test5_result, test6_result, test7_result, test8_result)

passed_tests <- sum(test_results)
total_tests <- length(test_results)
pass_rate <- (passed_tests / total_tests) * 100

cat(sprintf("\nTests Passed: %d/%d (%.1f%%)\n", passed_tests, total_tests, pass_rate))

if (pass_rate == 100) {
  cat("\n ALL TESTS PASSED! Data loading verification complete. \n")
} else if (pass_rate >= 75) {
  cat("\nMost tests passed, but review failed tests for data integrity issues.\n")
} else {
  cat("\n Multiple tests failed. Please review data loading process.\n")
}

# ==================== DETAILED TABLE SUMMARY ====================

print("\n========================================")
print("DATABASE TABLE SUMMARY")
print("========================================")

tables <- c("Restaurants", "Servers", "ServerEmployments", "Customers", 
            "MealTypes", "PaymentMethods", "Visits")

for (table in tables) {
  count <- dbGetQuery(mydb, paste("SELECT COUNT(*) as count FROM", table))$count
  cat(sprintf("%-20s: %6d rows\n", table, count))
}

# ==================== CLEANUP ====================

dbDisconnect(mydb)
print("\nDisconnected from database")
print("========================================")
print("Test execution completed successfully!")
print("========================================")