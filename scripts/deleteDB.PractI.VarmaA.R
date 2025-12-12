# deleteDB.PractI.VarmaA.R
# CS5200 Practicum I - Database Deletion Script
# Author: Ayush Varma
# Semester: Fall 2025

# Load required libraries
library(RMySQL)
library(DBI)

# Clear environment
rm(list = ls())

# ==================== DATABASE CONNECTION ====================

source("db_config.R")

print("Connecting to MySQL database...")

mydb <- dbConnect(
  RMySQL::MySQL(),
  user = db_user,
  password = "db_password",
  dbname = db_name,
  host = db_host,
  port = db_port
)

print("Connected successfully")

# ==================== LIST EXISTING TABLES ====================

existing_tables <- dbListTables(mydb)
print("Current tables in database:")
print(existing_tables)

if (length(existing_tables) == 0) {
  print("No tables found in database - nothing to delete")
} else {
  # Show row counts before deletion
  print("Row counts before deletion:")
  for (table in existing_tables) {
    count_query <- paste("SELECT COUNT(*) as count FROM", table)
    result <- dbGetQuery(mydb, count_query)
    print(paste(table, ":", result$count, "rows"))
  }
  
  # ==================== DROP TABLES ====================
  
  print("========================================")
  print("Starting table deletion...")
  print("========================================")
  
  # Disable foreign key checks to avoid dependency issues
  dbExecute(mydb, "SET FOREIGN_KEY_CHECKS = 0")
  print("Disabled foreign key checks")
  
  # Drop tables - order doesn't matter with FK checks disabled
  # but I wanted to maintain logical order for clarity
  
  # Drop Visits first (has most dependencies)
  if (dbExistsTable(mydb, "Visits")) {
    dbExecute(mydb, "DROP TABLE IF EXISTS Visits")
    print("Dropped table: Visits")
  }
  
  # Drop ServerEmployments (junction table)
  if (dbExistsTable(mydb, "ServerEmployments")) {
    dbExecute(mydb, "DROP TABLE IF EXISTS ServerEmployments")
    print("Dropped table: ServerEmployments")
  }
  
  # Drop Customers
  if (dbExistsTable(mydb, "Customers")) {
    dbExecute(mydb, "DROP TABLE IF EXISTS Customers")
    print("Dropped table: Customers")
  }
  
  # Drop Servers
  if (dbExistsTable(mydb, "Servers")) {
    dbExecute(mydb, "DROP TABLE IF EXISTS Servers")
    print("Dropped table: Servers")
  }
  
  # Drop Restaurants
  if (dbExistsTable(mydb, "Restaurants")) {
    dbExecute(mydb, "DROP TABLE IF EXISTS Restaurants")
    print("Dropped table: Restaurants")
  }
  
  # Drop MealTypes
  if (dbExistsTable(mydb, "MealTypes")) {
    dbExecute(mydb, "DROP TABLE IF EXISTS MealTypes")
    print("Dropped table: MealTypes")
  }
  
  # Drop PaymentMethods
  if (dbExistsTable(mydb, "PaymentMethods")) {
    dbExecute(mydb, "DROP TABLE IF EXISTS PaymentMethods")
    print("Dropped table: PaymentMethods")
  }
  
  # Re-enable foreign key checks
  dbExecute(mydb, "SET FOREIGN_KEY_CHECKS = 1")
  print("Re-enabled foreign key checks")
  
  # ==================== VERIFY DELETION ====================
  
  print("========================================")
  print("Verification...")
  print("========================================")
  
  # Check remaining tables
  remaining_tables <- dbListTables(mydb)
  
  if (length(remaining_tables) == 0) {
    print("SUCCESS: All tables have been deleted")
    print("Database is now empty and ready for recreation")
  } else {
    print("WARNING: Some tables still exist:")
    print(remaining_tables)
  }
}

# ==================== FINAL CHECK ====================

final_tables <- dbListTables(mydb)
print("========================================")
print("Final status:")
if (length(final_tables) == 0) {
  print("Database is completely empty")
} else {
  print(paste("Tables remaining:", paste(final_tables, collapse = ", ")))
}
print("========================================")

# ==================== CLEANUP ====================

dbDisconnect(mydb)
print("Disconnected from database")

print("========================================")
print("Database deletion script completed!")
print("Run createDB script to recreate tables")
print("========================================")

