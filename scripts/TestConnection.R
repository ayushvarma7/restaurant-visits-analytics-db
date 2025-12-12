
# Test Connection to Aiven MySQL
# CS5200 Practicum I
# Ayush Varma


if(!require(RMySQL)) install.packages("RMySQL")
if(!require(DBI)) install.packages("DBI")

library(RMySQL)
library(DBI)


# Credentials of database

source("db_config.R")


tryCatch({
db <- dbConnect(
  RMySQL::MySQL(),
  user = db_user,
  password = db_password,
  dbname = db_name,
  host = db_host,
  port = db_port
)


print("Successfully connected!")


# Test query
result <- dbGetQuery(db, "SELECT VERSION() as version")
print(paste("MySQL Version:", result$version))

result <- dbGetQuery(db, "SELECT 1+1")
print(result)
}, 
error = function(e){
  print(paste("Connection failed:", e$message))

})