# loadDB.PractI.VarmaA.R
# CS5200 Practicum I - Database Population Script
# Author: Ayush Varma
# Semester: Fall 2025
# Purpose: Load data into database

library(RMySQL)
library(DBI)
library(lubridate)
library(RSQLite)

# Clear environment
rm(list = ls())

# ==================== DATABASE CONNECTION ====================

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

# ==================== LOAD CSV DATA ====================

# csv_file <- "restaurant-visits-200.csv" 
csv_file <- "restaurant-visits-179719.csv"
df.orig <- read.csv(csv_file, stringsAsFactors = FALSE, na.strings = c("", "NA"))
print(paste("Loaded", nrow(df.orig), "rows from CSV"))



# Connect to SQLite database
sqlite_db <- dbConnect(RSQLite::SQLite(), "restaurants-db.sqlitedb")
print("Connected to SQLite database for restaurant data")

# Load restaurants from SQLite
all_restaurants <- dbGetQuery(sqlite_db, "SELECT * FROM restaurants")
print(paste("Found", nrow(all_restaurants), "restaurants in SQLite"))

if (nrow(all_restaurants) > 0) {
  success_count <- 0
  
  for (i in 1:nrow(all_restaurants)) {
    rest <- all_restaurants[i, ]
    
    # Convert yes/no to 1/0 for HasService
    has_service <- ifelse(rest$hasService == "yes", 1, 0)
    
    # Use rid directly as RestaurantID
    insert_query <- sprintf(
      "INSERT INTO Restaurants (RestaurantID, RestaurantName, City, State, HasService) 
       VALUES (%d, '%s', '%s', '%s', %d)",
      rest$rid,  # Use rid directly
      gsub("'", "''", rest$rname),
      gsub("'", "''", rest$city),
      gsub("'", "''", rest$state),
      has_service
    )
    
    tryCatch({
      dbExecute(mydb, insert_query)
      success_count <- success_count + 1
    }, error = function(e) {
      print(paste("Error inserting restaurant", rest$rname, ":", e$message))
    })
  }
  
  print(paste("Successfully inserted", success_count, "restaurants"))

}

  # Closing SQLite connection
  dbDisconnect(sqlite_db)
# ==================== DATA CLEANING FUNCTIONS ====================

# Function to clean date values
clean_date <- function(date_str) {
  if (is.na(date_str) || date_str == "" || 
      date_str == "0000-00-00" || date_str == "9999-99-99") {
    return(NA)
  }
  parsed <- as.Date(date_str, format = "%Y-%m-%d")
  if (is.na(parsed)) {
    parsed <- as.Date(date_str, format = "%m/%d/%Y")
  }
  return(parsed)
}

# Function to clean birth dates
clean_birth_date <- function(date_str) {
  if (is.na(date_str) || date_str == "") {
    return(NA)
  }
  return(as.Date(date_str, format = "%m/%d/%Y"))
}

# Function to clean party size
# I have taken outliers or sentinel values to represent by NA
clean_party_size <- function(size) {
  
  # Convert to numeric first
  size_num <- suppressWarnings(as.numeric(size))
  
  # Handle NA or sentinel value 99 - return NA (unknown)
  if (is.na(size_num) || size_num == 99) {
    return(NA)
  }
  
  # Handle unreasonable values (0, negative, or > 20) - return NA
  if (size_num <= 0 || size_num > 20) {
    return(NA)
  }
  
  # Return the original reasonable value (1-20)
  return(as.integer(size_num))
}

# Function to convert yes/no to boolean
to_boolean <- function(val) {
  if (is.na(val) || val == "") return(0)
  
  val_clean <- tolower(trimws(as.character(val)))
  
  # Handle TRUE/FALSE or yes/no
  if (val_clean %in% c("yes", "true", "1")) return(1)
  return(0)
}

# ==================== GET LOOKUP TABLE MAPPINGS ====================

meal_types <- dbGetQuery(mydb, "SELECT MealTypeID, MealTypeName FROM MealTypes")
payment_methods <- dbGetQuery(mydb, "SELECT PaymentMethodID, MethodName FROM PaymentMethods")

get_meal_type_id <- function(meal_name) {
  if (is.na(meal_name) || meal_name == "") meal_name <- "Lunch"
  id <- meal_types$MealTypeID[meal_types$MealTypeName == meal_name]
  if (length(id) == 0) return(2)
  return(id)
}

get_payment_method_id <- function(method_name) {
  if (is.na(method_name) || method_name == "") method_name <- "Cash"
  id <- payment_methods$PaymentMethodID[payment_methods$MethodName == method_name]
  if (length(id) == 0) return(1)
  return(id)
}

# ==================== STEP 1: POPULATE SERVERS ====================

print("========== Loading Servers ==========")

# Filter valid servers - using vectorized operations
valid_servers <- df.orig[!is.na(df.orig$ServerEmpID) & 
                           df.orig$ServerEmpID != "" & 
                           df.orig$ServerName != "N/A", ]

if (nrow(valid_servers) > 0) {
  unique_servers <- valid_servers[!duplicated(valid_servers$ServerEmpID), 
                                  c("ServerEmpID", "ServerName", "ServerBirthDate", "ServerTIN")]
  
  print(paste("Found", nrow(unique_servers), "unique servers"))
  
  servers_inserted <- 0
  for (i in 1:nrow(unique_servers)) {
    server <- unique_servers[i, ]
    
    birth_date <- clean_birth_date(server$ServerBirthDate)
    
    insert_query <- sprintf(
      "INSERT IGNORE INTO Servers (ServerEmpID, ServerName, ServerBirthDate, ServerTIN) 
       VALUES (%d, '%s', %s, '%s')",
      as.integer(server$ServerEmpID),
      gsub("'", "''", server$ServerName),
      ifelse(is.na(birth_date), "NULL", sprintf("'%s'", birth_date)),
      ifelse(is.na(server$ServerTIN), "", server$ServerTIN)
    )
    
    tryCatch({
      dbExecute(mydb, insert_query)
      servers_inserted <- servers_inserted + 1
    }, error = function(e) {
      print(paste("Error inserting server", server$ServerEmpID, ":", e$message))
    })
  }
  print(paste("Inserted", servers_inserted, "servers"))
}

# ==================== STEP 2: POPULATE SERVER EMPLOYMENTS ====================

print("========== Loading Server Employments ==========")

restaurants <- dbGetQuery(mydb, "SELECT RestaurantID, RestaurantName FROM Restaurants")

if (nrow(valid_servers) > 0) {
  employments <- unique(valid_servers[, c("ServerEmpID", "Restaurant", "StartDateHired", 
                                          "EndDateHired", "HourlyRate")])
  
  employments_inserted <- 0
  for (i in 1:nrow(employments)) {
    emp <- employments[i, ]
    
    rest_id <- restaurants$RestaurantID[restaurants$RestaurantName == emp$Restaurant]
    if (length(rest_id) == 0) {
      print(paste("Warning: Restaurant not found:", emp$Restaurant))
      next
    }
    
    start_date <- clean_date(emp$StartDateHired)
    end_date <- clean_date(emp$EndDateHired)
    
    if (is.na(start_date)) next
    
    insert_query <- sprintf(
      "INSERT IGNORE INTO ServerEmployments 
       (ServerEmpID, RestaurantID, StartDateHired, EndDateHired, HourlyRate) 
       VALUES (%d, %d, '%s', %s, %.2f)",
      as.integer(emp$ServerEmpID),
      rest_id,
      start_date,
      ifelse(is.na(end_date), "NULL", sprintf("'%s'", end_date)),
      ifelse(is.na(emp$HourlyRate), 0, emp$HourlyRate)
    )
    
    tryCatch({
      dbExecute(mydb, insert_query)
      employments_inserted <- employments_inserted + 1
    }, error = function(e) {
      # Ignore duplicate key errors
    })
  }
  print(paste("Inserted", employments_inserted, "employment records"))
}

# ==================== STEP 3: POPULATE CUSTOMERS ====================

print("========== Loading Customers ==========")

customers_data <- df.orig[!is.na(df.orig$CustomerEmail) & df.orig$CustomerEmail != "", ]

if (nrow(customers_data) > 0) {
  unique_customers <- unique(customers_data[, c("CustomerName", "CustomerPhone", 
                                                "CustomerEmail", "LoyaltyMember")])
  
  print(paste("Found", nrow(unique_customers), "unique customers"))
  
  customers_inserted <- 0
  for (i in 1:nrow(unique_customers)) {
    customer <- unique_customers[i, ]
    
    loyalty <- to_boolean(customer$LoyaltyMember)
    
    insert_query <- sprintf(
      "INSERT IGNORE INTO Customers (CustomerName, CustomerPhone, CustomerEmail, LoyaltyMember) 
       VALUES (%s, %s, '%s', %d)",
      ifelse(is.na(customer$CustomerName) || customer$CustomerName == "", 
             "NULL", sprintf("'%s'", gsub("'", "''", customer$CustomerName))),
      ifelse(is.na(customer$CustomerPhone) || customer$CustomerPhone == "", 
             "NULL", sprintf("'%s'", gsub("'", "''", customer$CustomerPhone))),
      gsub("'", "''", customer$CustomerEmail),
      loyalty
    )
    
    tryCatch({
      dbExecute(mydb, insert_query)
      customers_inserted <- customers_inserted + 1
    }, error = function(e) {
      # Ignore duplicate email errors
    })
  }
  print(paste("Inserted", customers_inserted, "customers"))
}

# ==================== STEP 4: POPULATE VISITS ====================

print("========== Loading Visits ==========")

customers_map <- dbGetQuery(mydb, "SELECT CustomerID, CustomerEmail FROM Customers")

visits_inserted <- 0
visits_errors <- 0

# for (i in 1:nrow(df.orig)) {
#   visit <- df.orig[i, ]
#   
#   # Get RestaurantID
#   restaurant_id <- restaurants$RestaurantID[restaurants$RestaurantName == visit$Restaurant]
#   if (length(restaurant_id) == 0) {
#     print(paste("Error: Restaurant not found:", visit$Restaurant))
#     visits_errors <- visits_errors + 1
#     next
#   }
#   
#   # Get CustomerID
#   customer_id <- "NULL"
#   if (!is.na(visit$CustomerEmail) && visit$CustomerEmail != "") {
#     cust_match <- customers_map$CustomerID[customers_map$CustomerEmail == visit$CustomerEmail]
#     if (length(cust_match) > 0) {
#       customer_id <- cust_match[1]
#     }
#   }
#   
#   # Get ServerID  
#   server_id <- "NULL"
#   if (!is.na(visit$ServerEmpID) && visit$ServerEmpID != "" && visit$ServerName != "N/A") {
#     server_id <- as.integer(visit$ServerEmpID)
#   }
#   
#   # Clean and prepare data
#   party_size <- clean_party_size(visit$PartySize)
#   wait_time <- ifelse(is.na(visit$WaitTime), 0, visit$WaitTime)
#   visit_time <- ifelse(is.na(visit$VisitTime) || visit$VisitTime == "", 
#                        "NULL", sprintf("'%s:00'", visit$VisitTime))
#   meal_type_id <- get_meal_type_id(visit$MealType)
#   payment_method_id <- get_payment_method_id(visit$PaymentMethod)
#   ordered_alcohol <- to_boolean(visit$orderedAlcohol)
#   
#   # Build insert query
#   insert_query <- sprintf(
#     "INSERT INTO Visits (RestaurantID, CustomerID, ServerEmpID, VisitDate, VisitTime, 
#                         MealTypeID, PartySize, Genders, WaitTime, FoodBill, AlcoholBill,
#                         TipAmount, DiscountApplied, PaymentMethodID, OrderedAlcohol) 
#      VALUES (%d, %s, %s, '%s', %s, %d, %d, '%s', %d, %.2f, %.2f, %.2f, %.2f, %d, %d)",
#     restaurant_id,
#     customer_id,
#     server_id,
#     visit$VisitDate,
#     visit_time,
#     meal_type_id,
#     party_size,
#     ifelse(is.na(visit$Genders), "", visit$Genders),
#     wait_time,
#     ifelse(is.na(visit$FoodBill), 0, visit$FoodBill),
#     ifelse(is.na(visit$AlcoholBill), 0, visit$AlcoholBill),
#     ifelse(is.na(visit$TipAmount), 0, visit$TipAmount),
#     ifelse(is.na(visit$DiscountApplied), 0, visit$DiscountApplied),
#     payment_method_id,
#     ordered_alcohol
#   )
#   
#   tryCatch({
#     dbExecute(mydb, insert_query)
#     visits_inserted <- visits_inserted + 1
#     
#     if (visits_inserted %% 50 == 0) {
#       print(paste("Progress:", visits_inserted, "visits inserted"))
#     }
#   }, error = function(e) {
#     visits_errors <- visits_errors + 1
#     if (visits_errors <= 5) {
#       print(paste("Error inserting visit", i, ":", e$message))
#     }
#   })
# }
# 
# print(paste("Inserted", visits_inserted, "visits"))
# print(paste("Errors:", visits_errors))



batch_size <- 1000
total_rows <- nrow(df.orig)
visits_inserted <- 0
errors <- 0

print("Starting batch insert into Visits table...")

dbExecute(mydb, "SET autocommit = 0;")  # disable autocommit for speed

for (start in seq(1, total_rows, by = batch_size)) {
  end <- min(start + batch_size - 1, total_rows)
  batch <- df.orig[start:end, ]
  
  values <- apply(batch, 1, function(visit) {
    restaurant_id <- restaurants$RestaurantID[restaurants$RestaurantName == visit["Restaurant"]]
    if (length(restaurant_id) == 0) return(NULL)
    
    customer_id <- "NULL"
    cust_match <- customers_map$CustomerID[customers_map$CustomerEmail == visit["CustomerEmail"]]
    if (length(cust_match) > 0) customer_id <- cust_match[1]
    
    server_id <- ifelse(!is.na(visit["ServerEmpID"]) && visit["ServerEmpID"] != "", 
                        as.integer(visit["ServerEmpID"]), "NULL")
    
    party_size <- clean_party_size(as.character(visit["PartySize"]))
    wait_time <- ifelse(is.na(visit["WaitTime"]), 0, visit["WaitTime"])
    meal_type_id <- get_meal_type_id(visit["MealType"])
    payment_method_id <- get_payment_method_id(visit["PaymentMethod"])
    ordered_alcohol <- to_boolean(visit["orderedAlcohol"])
    
    sprintf("(%s, %s, %s, '%s', %s, %s, %s, '%s', %s, %s, %s, %s, %s, %s, %s)",
            ifelse(is.na(restaurant_id), "NULL", restaurant_id),
            ifelse(is.na(customer_id), "NULL", customer_id),
            ifelse(is.na(server_id), "NULL", server_id),
            visit["VisitDate"],
            ifelse(is.na(visit["VisitTime"]) || visit["VisitTime"] == "", "NULL",
                   sprintf("'%s:00'", visit["VisitTime"])),
            ifelse(is.na(meal_type_id), "NULL", meal_type_id),
            ifelse(is.na(party_size), "NULL", party_size),
            visit["Genders"],
            ifelse(is.na(wait_time), "NULL", wait_time),
            ifelse(is.na(visit["FoodBill"]), 0, visit["FoodBill"]),
            ifelse(is.na(visit["AlcoholBill"]), 0, visit["AlcoholBill"]),
            ifelse(is.na(visit["TipAmount"]), 0, visit["TipAmount"]),
            ifelse(is.na(visit["DiscountApplied"]), 0, visit["DiscountApplied"]),
            ifelse(is.na(payment_method_id), "NULL", payment_method_id),
            ifelse(is.na(ordered_alcohol), "NULL", ordered_alcohol))
    
  })
  
  values <- values[!sapply(values, is.null)]
  if (length(values) == 0) next
  
  insert_query <- paste0(
    "INSERT INTO Visits (RestaurantID, CustomerID, ServerEmpID, VisitDate, VisitTime, 
      MealTypeID, PartySize, Genders, WaitTime, FoodBill, AlcoholBill, TipAmount, 
      DiscountApplied, PaymentMethodID, OrderedAlcohol) VALUES ",
    paste(values, collapse = ", ")
  )
  
  tryCatch({
    dbExecute(mydb, insert_query)
    visits_inserted <- visits_inserted + length(values)
    print(paste("Inserted rows:", start, "-", end, "| Total:", visits_inserted))
  }, error = function(e) {
    print(paste("Error in batch", start, "-", end, ":", e$message))
    errors <<- errors + 1
  })
}

dbExecute(mydb, "COMMIT;")
dbExecute(mydb, "SET autocommit = 1;")  # re-enable autocommit

print("========================================")
print("Data Loading Summary")
print("========================================")
print(paste("Inserted", visits_inserted, "visits"))
print(paste("Errors:", errors))



# ==================== VERIFICATION ====================

print("========================================")
print("Data Loading Summary")
print("========================================")

tables <- c("Restaurants", "Servers", "ServerEmployments", "Customers", 
            "MealTypes", "PaymentMethods", "Visits")

for (table in tables) {
  count <- dbGetQuery(mydb, paste("SELECT COUNT(*) as count FROM", table))$count
  print(paste(table, ":", count, "rows"))
}

# ==================== CLEANUP ====================

dbDisconnect(mydb)

print("========================================")
print("Database population completed!")
print(paste("Processed", nrow(df.orig), "visit records"))
print("========================================")