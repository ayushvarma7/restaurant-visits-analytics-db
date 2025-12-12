# Technical Design Documentation

## Table of Contents
1. [Problem Statement](#problem-statement)
2. [Data Analysis](#data-analysis)
3. [Functional Dependencies](#functional-dependencies)
4. [Normalization Process](#normalization-process)
5. [Schema Design](#schema-design)
6. [ETL Pipeline](#etl-pipeline)
7. [Stored Procedures](#stored-procedures)
8. [Performance Considerations](#performance-considerations)

---

## Problem Statement

A restaurant management group operating 13 locations across Florida and Georgia needed to replace their legacy third-party SAAS point-of-sale system. The existing system could only export data as denormalized CSV dumps, leading to:

- **Data redundancy**: Server and customer information repeated across 179,719 rows
- **Update anomalies**: Changing a server's hourly rate required updating thousands of rows
- **No referential integrity**: Invalid relationships possible
- **Poor query performance**: Aggregations required scanning entire dataset

### Solution Requirements
1. Design a normalized relational schema (3NF minimum)
2. Host on cloud MySQL for team accessibility
3. Build ETL pipeline to migrate historical data
4. Create stored procedures for ongoing transaction recording
5. Enable analytics and reporting capabilities

---

## Data Analysis

### Source Data Inventory

**CSV File: `restaurant-visits-179719.csv`**
```
Records: 179,719
Columns: 24
Size: ~45MB uncompressed
```

**SQLite Database: `restaurants-db.sqlitedb`**
```
Table: restaurants
Records: 13
Columns: rid, rname, city, state, hasService
```

### Attribute Catalog

| Attribute | Source | Data Type | Null Rate | Notes |
|-----------|--------|-----------|-----------|-------|
| Restaurant | CSV | VARCHAR | 0% | Maps to SQLite |
| ServerEmpID | CSV | INT | 38.2% | Self-service/takeout |
| ServerName | CSV | VARCHAR | 38.2% | "N/A" sentinel |
| StartDateHired | CSV | DATE | 38.2% | Employment start |
| EndDateHired | CSV | DATE | 85%+ | Most still employed |
| HourlyRate | CSV | DECIMAL | 38.2% | Per employment period |
| ServerBirthDate | CSV | DATE | 38.2% | MM/DD/YYYY format |
| ServerTIN | CSV | VARCHAR | 38.2% | Tax ID |
| VisitDate | CSV | DATE | 0% | YYYY-MM-DD |
| VisitTime | CSV | TIME | <1% | HH:MM format |
| MealType | CSV | VARCHAR | 0% | 4 distinct values |
| PartySize | CSV | INT | <1% | 99 = sentinel |
| Genders | CSV | VARCHAR | <1% | "MMFF" format |
| WaitTime | CSV | INT | <1% | Minutes |
| CustomerName | CSV | VARCHAR | 66.3% | Anonymous visits |
| CustomerPhone | CSV | VARCHAR | 66.3% | |
| CustomerEmail | CSV | VARCHAR | 66.3% | Unique identifier |
| LoyaltyMember | CSV | BOOLEAN | 66.3% | yes/no strings |
| FoodBill | CSV | DECIMAL | 0% | |
| AlcoholBill | CSV | DECIMAL | 0% | |
| TipAmount | CSV | DECIMAL | 0% | |
| DiscountApplied | CSV | DECIMAL | 0% | Percentage |
| PaymentMethod | CSV | VARCHAR | 0% | 3 distinct values |
| orderedAlcohol | CSV | BOOLEAN | 0% | yes/no strings |

### Data Quality Issues Discovered

1. **Sentinel Values**
   - Party size `99` = unknown
   - Date `0000-00-00` = invalid/missing
   - ServerName `N/A` = no server

2. **Format Inconsistencies**
   - Birth dates: MM/DD/YYYY vs YYYY-MM-DD
   - Boolean fields: "yes"/"no" strings vs true/false

3. **Restaurant Discrepancy**
   - SQLite: 13 restaurants
   - CSV: 12 restaurants (Restaurant ID 8 "Patty Palace" has no visits)

---

## Functional Dependencies

### Identified Dependencies

```
FD1: ServerEmpID → ServerName, ServerBirthDate, ServerTIN
FD2: (ServerEmpID, RestaurantID, StartDateHired) → EndDateHired, HourlyRate
FD3: CustomerEmail → CustomerName, CustomerPhone, LoyaltyMember
FD4: CustomerPhone → CustomerName, CustomerEmail, LoyaltyMember
FD5: RestaurantName → RestaurantID, City, State, HasService
FD6: rid → rname, city, state, hasService  (SQLite source)
FD7: (RestaurantID, VisitDate, VisitTime, CustomerID) → [all visit attributes]
FD8: MealTypeID → MealTypeName
FD9: PaymentMethodID → MethodName
```

### Analysis of FD2 (Critical Finding)

The employment relationship required careful analysis:

```sql
-- Query to verify employment patterns
SELECT ServerEmpID, Restaurant, StartDateHired, EndDateHired, HourlyRate
FROM visits
WHERE ServerEmpID = 1001
GROUP BY ServerEmpID, Restaurant, StartDateHired, EndDateHired, HourlyRate;
```

**Finding**: Servers can:
- Work at multiple restaurants simultaneously
- Leave and return to the same restaurant
- Have different hourly rates for different employment periods

This necessitated a **junction table with attributes** rather than a simple M:N relationship.

---

## Normalization Process

### Step 1: First Normal Form (1NF)

**Violation Identified**: `Genders` field contains multi-valued data

```
Genders = "MMFF" → {M, M, F, F}
```

**Proper 1NF Decomposition**:
```sql
CREATE TABLE PartyMembers (
    VisitID INT,
    MemberPosition INT,
    Gender CHAR(1),
    PRIMARY KEY (VisitID, MemberPosition)
);
```

**Design Decision**: Preserved as VARCHAR(50)
- Decomposition creates ~500,000 rows
- Minimal analytical value for gender breakdown per position
- Query complexity increase not justified

### Step 2: Second Normal Form (2NF)

Eliminated partial dependencies by separating entities:

| Entity | Depends On |
|--------|------------|
| Server info | ServerEmpID only |
| Customer info | CustomerEmail only |
| Restaurant info | RestaurantID only |
| Employment details | (ServerEmpID, RestaurantID, StartDateHired) |

### Step 3: Third Normal Form (3NF)

Removed transitive dependencies:

**Before**: `Visit → ServerEmpID → ServerName`
**After**: Server attributes in separate `Servers` table

---

## Schema Design

### Final Schema (7 Tables)

```sql
-- 1. Restaurants
CREATE TABLE Restaurants (
    RestaurantID INT PRIMARY KEY,
    RestaurantName VARCHAR(100) NOT NULL UNIQUE,
    City VARCHAR(100),
    State VARCHAR(50),
    HasService BOOLEAN DEFAULT TRUE,
    INDEX idx_state (State)
);

-- 2. Servers
CREATE TABLE Servers (
    ServerEmpID INT PRIMARY KEY,
    ServerName VARCHAR(100) NOT NULL,
    ServerBirthDate DATE,
    ServerTIN VARCHAR(20),
    INDEX idx_server_name (ServerName)
);

-- 3. ServerEmployments (Junction Table)
CREATE TABLE ServerEmployments (
    ServerEmpID INT,
    RestaurantID INT,
    StartDateHired DATE,
    EndDateHired DATE,
    HourlyRate DECIMAL(5,2) DEFAULT 0.00,
    PRIMARY KEY (ServerEmpID, RestaurantID, StartDateHired),
    FOREIGN KEY (ServerEmpID) REFERENCES Servers(ServerEmpID)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (RestaurantID) REFERENCES Restaurants(RestaurantID)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- 4. Customers
CREATE TABLE Customers (
    CustomerID INT AUTO_INCREMENT PRIMARY KEY,
    CustomerName VARCHAR(100),
    CustomerPhone VARCHAR(30),
    CustomerEmail VARCHAR(150) UNIQUE,
    LoyaltyMember BOOLEAN DEFAULT FALSE,
    DateAdded TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_email (CustomerEmail)
);

-- 5. MealTypes (Lookup)
CREATE TABLE MealTypes (
    MealTypeID INT AUTO_INCREMENT PRIMARY KEY,
    MealTypeName VARCHAR(20) NOT NULL UNIQUE
);

-- 6. PaymentMethods (Lookup)
CREATE TABLE PaymentMethods (
    PaymentMethodID INT AUTO_INCREMENT PRIMARY KEY,
    MethodName VARCHAR(30) NOT NULL UNIQUE
);

-- 7. Visits (Fact Table)
CREATE TABLE Visits (
    VisitID INT AUTO_INCREMENT PRIMARY KEY,
    RestaurantID INT NOT NULL,
    CustomerID INT,           -- Nullable: anonymous visits
    ServerEmpID INT,          -- Nullable: self-service/takeout
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
    INDEX idx_composite (RestaurantID, VisitDate)
);
```

### Referential Integrity Rules

| Foreign Key | ON DELETE | ON UPDATE | Rationale |
|-------------|-----------|-----------|-----------|
| Visits.RestaurantID | RESTRICT | CASCADE | Preserve history |
| Visits.CustomerID | SET NULL | CASCADE | Allow deletion |
| Visits.ServerEmpID | SET NULL | CASCADE | Allow departure |
| ServerEmployments.ServerEmpID | CASCADE | CASCADE | Remove with server |
| ServerEmployments.RestaurantID | CASCADE | CASCADE | Remove with restaurant |

---

## ETL Pipeline

### Pipeline Stages

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   EXTRACT   │───▶│  TRANSFORM  │───▶│    LOAD     │───▶│   VERIFY    │
│             │    │             │    │             │    │             │
│ • CSV file  │    │ • Clean     │    │ • Batch     │    │ • Count     │
│ • SQLite DB │    │ • Validate  │    │ • Transaction│   │ • Sum       │
│             │    │ • Map FKs   │    │ • Index     │    │ • Integrity │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

### Load Order (Dependency Resolution)

1. **Restaurants** (from SQLite) - No dependencies
2. **Servers** (from CSV) - No dependencies
3. **ServerEmployments** (from CSV) - Requires Servers, Restaurants
4. **Customers** (from CSV) - No dependencies
5. **MealTypes** (static) - No dependencies
6. **PaymentMethods** (static) - No dependencies
7. **Visits** (from CSV) - Requires all above

### Batch Insert Implementation

```r
# Batch processing for optimal performance
batch_size <- 1000
total_rows <- nrow(df.orig)

dbExecute(mydb, "SET autocommit = 0;")

for (start in seq(1, total_rows, by = batch_size)) {
  end <- min(start + batch_size - 1, total_rows)
  batch <- df.orig[start:end, ]
  
  # Build batch INSERT statement
  values <- sapply(1:nrow(batch), function(i) {
    # Transform and format each row
    sprintf("(%s, %s, %s, '%s', ...)", ...)
  })
  
  insert_query <- paste0(
    "INSERT INTO Visits (...) VALUES ",
    paste(values, collapse = ", ")
  )
  
  dbExecute(mydb, insert_query)
}

dbExecute(mydb, "COMMIT;")
dbExecute(mydb, "SET autocommit = 1;")
```

### Data Cleaning Functions

```r
# Party size cleaning (sentinel value handling)
clean_party_size <- function(size) {
  size_num <- as.numeric(size)
  if (is.na(size_num) || size_num == 99) return(NA)
  if (size_num <= 0 || size_num > 20) return(NA)
  return(as.integer(size_num))
}

# Date cleaning (invalid date handling)
clean_date <- function(date_str) {
  if (is.na(date_str) || date_str == "0000-00-00") return(NA)
  return(as.Date(date_str, format = "%Y-%m-%d"))
}

# Boolean conversion
to_boolean <- function(val) {
  if (is.na(val)) return(0)
  return(ifelse(tolower(val) %in% c("yes", "true", "1"), 1, 0))
}
```

---

## Stored Procedures

### storeVisit - Transaction Recording

Assumes all foreign key entities exist.

```sql
CREATE PROCEDURE storeVisit(
    IN p_RestaurantID INT,
    IN p_CustomerID INT,
    IN p_ServerEmpID INT,
    IN p_VisitDate DATE,
    -- ... other parameters
)
BEGIN
    -- Validate restaurant exists
    IF NOT EXISTS (SELECT 1 FROM Restaurants WHERE RestaurantID = p_RestaurantID) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error: Restaurant ID does not exist';
    END IF;
    
    -- Insert visit
    INSERT INTO Visits (...) VALUES (...);
    
    SELECT LAST_INSERT_ID() AS NewVisitID;
END
```

### storeNewVisit - Upsert Pattern

Creates entities if they don't exist.

```sql
CREATE PROCEDURE storeNewVisit(
    -- Restaurant, Customer, Server, and Visit parameters
)
BEGIN
    DECLARE v_RestaurantID INT;
    DECLARE v_CustomerID INT;
    DECLARE v_ServerID INT;
    
    -- Find or create restaurant
    SELECT RestaurantID INTO v_RestaurantID
    FROM Restaurants WHERE RestaurantName = p_RestaurantName;
    
    IF v_RestaurantID IS NULL THEN
        INSERT INTO Restaurants (...) VALUES (...);
        SET v_RestaurantID = LAST_INSERT_ID();
    END IF;
    
    -- Similar logic for Customer and Server...
    
    -- Insert visit with resolved IDs
    INSERT INTO Visits (...) VALUES (...);
END
```

---

## Performance Considerations

### Indexing Strategy

| Index | Type | Purpose |
|-------|------|---------|
| `idx_visit_date` | B-tree | Date range queries |
| `idx_composite` | B-tree | Restaurant + Date filters |
| `idx_restaurant_name` | B-tree | Name lookups |
| `idx_email` | B-tree | Customer lookups |
| `idx_state` | B-tree | Geographic filtering |

### Query Optimization Examples

**Before (Full Table Scan)**:
```sql
SELECT * FROM Visits WHERE RestaurantID = 5 AND VisitDate > '2024-01-01';
```

**After (Index Seek)**:
```sql
-- Uses idx_composite (RestaurantID, VisitDate)
SELECT VisitID, FoodBill, AlcoholBill 
FROM Visits 
WHERE RestaurantID = 5 AND VisitDate > '2024-01-01';
```

### Storage Savings from Normalization

| Before | After | Savings |
|--------|-------|---------|
| Server info × 179,719 rows | 68 rows | ~99.96% |
| Customer info × 60,574 rows | 24 rows | ~99.96% |
| Restaurant info × 179,719 rows | 13 rows | ~99.99% |
| MealType strings (avg 8 bytes) | INT (4 bytes) | ~50% |
| PaymentMethod strings (avg 12 bytes) | INT (4 bytes) | ~66% |

**Estimated total storage reduction**: ~85%

---

## Future Enhancements

1. **Partitioning**: Partition Visits by year for improved query performance
2. **Materialized Views**: Pre-aggregated revenue summaries
3. **Audit Trail**: Trigger-based change tracking
4. **API Layer**: REST API for application integration
5. **Real-time Analytics**: Stream processing for live dashboards