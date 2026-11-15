/*
PROJECT: Layoffs Data Cleaning
DATABASE: MySQL

Purpose:
1. Create a working staging table.
2. Identify and remove duplicate records.
3. Standardize text and date fields.
4. Handle missing values.
5. Add useful calculated workforce columns.

IMPORTANT:
- Run this script against the database containing the original `layoffs` table.
- The script drops and recreates `layoffs_staging2`.
- Keep a backup of your original data before running data-changing statements.
*/

-- =========================================================
-- 1. CREATE A STAGING TABLE
-- =========================================================

SELECT *
FROM layoffs;

CREATE TABLE IF NOT EXISTS layoffs_staging
LIKE layoffs;

TRUNCATE TABLE layoffs_staging;

INSERT INTO layoffs_staging
SELECT *
FROM layoffs;

SELECT *
FROM layoffs_staging;


-- =========================================================
-- 2. IDENTIFY DUPLICATES
-- =========================================================

-- Initial duplicate check using the main identifying fields.
SELECT
    *,
    ROW_NUMBER() OVER (
        PARTITION BY
            company,
            industry,
            total_laid_off,
            percentage_laid_off,
            `date`
        ORDER BY company
    ) AS row_num
FROM layoffs_staging;

-- More complete duplicate check using all relevant source fields.
WITH duplicate_cte AS
(
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                company,
                location,
                industry,
                total_laid_off,
                percentage_laid_off,
                `date`,
                stage,
                funds_raised_millions,
                country
            ORDER BY company
        ) AS row_num
    FROM layoffs_staging
)
SELECT *
FROM duplicate_cte
WHERE row_num > 1;


-- =========================================================
-- 3. CREATE A CLEANING TABLE WITH A ROW NUMBER
-- =========================================================

-- Drop the previous working table first so the script can be rerun.
DROP TABLE IF EXISTS layoffs_staging2;

CREATE TABLE layoffs_staging2
(
    company TEXT,
    location TEXT,
    industry TEXT,
    total_laid_off TEXT,
    percentage_laid_off TEXT,
    `date` TEXT,
    stage TEXT,
    country TEXT,
    funds_raised_millions INT DEFAULT NULL,
    row_num INT
) ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO layoffs_staging2
SELECT
    *,
    ROW_NUMBER() OVER (
        PARTITION BY
            company,
            location,
            industry,
            total_laid_off,
            percentage_laid_off,
            `date`,
            stage,
            funds_raised_millions,
            country
        ORDER BY company
    ) AS row_num
FROM layoffs_staging;

-- Review duplicates before deleting them.
SELECT *
FROM layoffs_staging2
WHERE row_num > 1;

-- Remove duplicate records.
SET SQL_SAFE_UPDATES = 0;

DELETE FROM layoffs_staging2
WHERE row_num > 1;

-- Confirm that no duplicates remain according to the selected fields.
SELECT *
FROM layoffs_staging2
WHERE row_num > 1;


-- =========================================================
-- 4. STANDARDIZE TEXT FIELDS
-- =========================================================

-- Remove leading and trailing spaces from company names.
UPDATE layoffs_staging2
SET company = TRIM(company);

-- Remove leading and trailing spaces from locations.
UPDATE layoffs_staging2
SET location = TRIM(location);

-- Review industry values.
SELECT DISTINCT
    industry,
    TRIM(industry) AS cleaned_industry
FROM layoffs_staging2;

-- Standardize cryptocurrency industry labels.
UPDATE layoffs_staging2
SET industry = 'Crypto'
WHERE industry LIKE 'Crypto%';

-- Review country values before standardizing.
SELECT DISTINCT country
FROM layoffs_staging2
ORDER BY country;

-- Standardize United States labels.
UPDATE layoffs_staging2
SET country = 'United States'
WHERE country LIKE 'United States%';

-- Remove trailing periods from country names.
UPDATE layoffs_staging2
SET country = TRIM(TRAILING '.' FROM country);

-- Remove leading # characters from company names.
UPDATE layoffs_staging2
SET company = TRIM(LEADING '#' FROM company);

-- Review stage values.
SELECT DISTINCT stage
FROM layoffs_staging2
ORDER BY stage;


-- =========================================================
-- 5. HANDLE EMPTY STRINGS AND NULL VALUES
-- =========================================================

-- Convert blank or whitespace-only values to NULL.
UPDATE layoffs_staging2
SET industry = NULL
WHERE industry IS NOT NULL
  AND TRIM(industry) = '';

UPDATE layoffs_staging2
SET country = NULL
WHERE country IS NOT NULL
  AND TRIM(country) = '';

UPDATE layoffs_staging2
SET total_laid_off = NULL
WHERE total_laid_off IS NOT NULL
  AND TRIM(total_laid_off) = '';

UPDATE layoffs_staging2
SET percentage_laid_off = NULL
WHERE percentage_laid_off IS NOT NULL
  AND TRIM(percentage_laid_off) = '';

-- Review missing industry values.
SELECT *
FROM layoffs_staging2
WHERE industry IS NULL;

-- Find records where both layoff measures are missing.
SELECT *
FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

-- Populate missing industry values when another row for the same
-- company has a known industry.
SELECT
    t1.company,
    t1.industry AS missing_industry,
    t2.industry AS available_industry
FROM layoffs_staging2 AS t1
JOIN layoffs_staging2 AS t2
    ON t1.company = t2.company
WHERE (t1.industry IS NULL OR t1.industry = '')
  AND t2.industry IS NOT NULL
  AND t2.industry <> '';

UPDATE layoffs_staging2 AS t1
JOIN layoffs_staging2 AS t2
    ON t1.company = t2.company
SET t1.industry = t2.industry
WHERE (t1.industry IS NULL OR t1.industry = '')
  AND t2.industry IS NOT NULL
  AND t2.industry <> '';

-- Remove records that contain no layoff quantity or percentage.
DELETE FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

-- Review remaining missing industry values.
SELECT *
FROM layoffs_staging2
WHERE industry IS NULL
   OR industry = '';

-- Review missing funds raised values (these are not automatically deleted).
SELECT *
FROM layoffs_staging2
WHERE funds_raised_millions IS NULL;


-- =========================================================
-- 6. CONVERT DATA TYPES
-- =========================================================

-- Convert the source date strings to MySQL DATE values.
-- This format matches the original data: month/day/year.
UPDATE layoffs_staging2
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y')
WHERE `date` IS NOT NULL
  AND TRIM(`date`) <> '';

ALTER TABLE layoffs_staging2
MODIFY COLUMN `date` DATE;

-- Convert numeric text fields to numeric data types.
-- Empty strings were converted to NULL in the previous section.
ALTER TABLE layoffs_staging2
MODIFY COLUMN total_laid_off INT NULL,
MODIFY COLUMN percentage_laid_off DECIMAL(5,4) NULL;


-- =========================================================
-- 7. REVIEW THE CLEANED DATA
-- =========================================================

SELECT *
FROM layoffs_staging2;

SELECT *
FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

SELECT *
FROM layoffs_staging2
WHERE percentage_laid_off IS NULL;

SELECT *
FROM layoffs_staging2
WHERE funds_raised_millions IS NULL;

SELECT *
FROM layoffs_staging2
WHERE company = 'Airbnb';

SELECT *
FROM layoffs_staging2
WHERE company = 'Carvana';


-- =========================================================
-- 8. CALCULATE TOTAL WORKFORCE
-- =========================================================

-- Estimate the total workforce using:
-- total_laid_off / percentage_laid_off.
-- Percentage values are stored as fractions (for example, 0.10 = 10%).

SELECT
    `date`,
    company,
    location,
    total_laid_off,
    percentage_laid_off,
    ROUND(total_laid_off / percentage_laid_off) AS estimated_total_workforce
FROM layoffs_staging2
WHERE total_laid_off IS NOT NULL
  AND percentage_laid_off IS NOT NULL
  AND percentage_laid_off <> 0;

ALTER TABLE layoffs_staging2
ADD COLUMN total_workforce BIGINT NULL
AFTER percentage_laid_off;

UPDATE layoffs_staging2
SET total_workforce = ROUND(total_laid_off / percentage_laid_off)
WHERE total_laid_off IS NOT NULL
  AND percentage_laid_off IS NOT NULL
  AND percentage_laid_off <> 0;


-- =========================================================
-- 9. CALCULATE REMAINING WORKFORCE
-- =========================================================

ALTER TABLE layoffs_staging2
ADD COLUMN remaining_workforce BIGINT NULL
AFTER total_workforce;

UPDATE layoffs_staging2
SET remaining_workforce = total_workforce - total_laid_off
WHERE total_workforce IS NOT NULL
  AND total_laid_off IS NOT NULL;

-- Review records with the largest estimated workforces.
SELECT
    DATE_FORMAT(`date`, '%Y-%m') AS timescale,
    company,
    total_laid_off,
    percentage_laid_off,
    total_workforce,
    remaining_workforce
FROM layoffs_staging2
WHERE total_laid_off IS NOT NULL
  AND percentage_laid_off IS NOT NULL
  AND total_workforce IS NOT NULL
ORDER BY total_workforce DESC;

-- Final cleaned table.
SELECT *
FROM layoffs_staging2
ORDER BY `date`, company;

-- Restore MySQL safe-update mode for subsequent work.
SET SQL_SAFE_UPDATES = 1;
