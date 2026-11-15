/*
PROJECT: Layoffs Exploratory Data Analysis (EDA)
DATABASE: MySQL

Purpose:
Explore the cleaned layoffs dataset to identify trends by company,
industry, country, year, and month.

Expected input:
A cleaned table named `layoffs_staging2` created by 01_Data_Cleaning.sql.
*/

-- =========================================================
-- 1. GET TO KNOW THE DATA
-- =========================================================

SELECT *
FROM layoffs_staging2;

-- Number of records and available layoff figures.
SELECT
    COUNT(*) AS total_records,
    MAX(total_laid_off) AS highest_single_record_layoff,
    COUNT(percentage_laid_off) AS records_with_percentage
FROM layoffs_staging2;

-- Date range covered by the dataset.
SELECT
    MIN(`date`) AS earliest_layoff_date,
    MAX(`date`) AS latest_layoff_date
FROM layoffs_staging2;


-- =========================================================
-- 2. COMPANY-LEVEL ANALYSIS
-- =========================================================

-- Inspect records for Airbnb.
SELECT
    company,
    total_laid_off
FROM layoffs_staging2
WHERE company = 'Airbnb';

-- Total layoffs at Airbnb across all records.
SELECT
    company,
    SUM(total_laid_off) AS total_layoffs
FROM layoffs_staging2
WHERE company = 'Airbnb'
GROUP BY company;

-- Companies with the highest total layoffs.
SELECT
    company,
    SUM(total_laid_off) AS total_layoffs
FROM layoffs_staging2
WHERE total_laid_off IS NOT NULL
GROUP BY company
ORDER BY total_layoffs DESC;


-- =========================================================
-- 3. INDUSTRY ANALYSIS
-- =========================================================

-- Explore layoff totals by industry and reported percentage.
SELECT
    industry,
    percentage_laid_off,
    SUM(total_laid_off) AS total_layoffs
FROM layoffs_staging2
WHERE percentage_laid_off IS NOT NULL
GROUP BY industry, percentage_laid_off
ORDER BY percentage_laid_off ASC;

-- Total layoffs by industry.
SELECT
    industry,
    SUM(total_laid_off) AS total_layoffs
FROM layoffs_staging2
WHERE total_laid_off IS NOT NULL
GROUP BY industry
ORDER BY total_layoffs DESC;


-- =========================================================
-- 4. COUNTRY ANALYSIS
-- =========================================================

-- Countries with the highest total layoffs.
SELECT
    country,
    SUM(total_laid_off) AS total_layoffs
FROM layoffs_staging2
WHERE total_laid_off IS NOT NULL
GROUP BY country
ORDER BY total_layoffs DESC;


-- =========================================================
-- 5. YEARLY ANALYSIS
-- =========================================================

-- Total layoffs by year.
SELECT
    YEAR(`date`) AS year,
    SUM(total_laid_off) AS total_layoffs
FROM layoffs_staging2
WHERE `date` IS NOT NULL
  AND total_laid_off IS NOT NULL
GROUP BY YEAR(`date`)
ORDER BY year;


-- =========================================================
-- 6. TOP FIVE COMPANIES BY LAYOFFS IN EACH YEAR
-- =========================================================

WITH company_year AS
(
    SELECT
        company,
        YEAR(`date`) AS years,
        SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
      AND total_laid_off IS NOT NULL
    GROUP BY company, YEAR(`date`)
),
company_year_rank AS
(
    SELECT
        *,
        DENSE_RANK() OVER (
            PARTITION BY years
            ORDER BY total_laid_off DESC
        ) AS ranking
    FROM company_year
    WHERE years IS NOT NULL
)
SELECT
    company,
    years,
    total_laid_off,
    ranking
FROM company_year_rank
WHERE ranking <= 5
ORDER BY years, ranking, company;


-- =========================================================
-- 7. EXPLORE DENSE_RANK()
-- =========================================================

-- Rank companies alphabetically within each distinct layoff total.
-- This is a window-function practice query, not a business ranking.
SELECT
    company,
    total_laid_off,
    DENSE_RANK() OVER (
        PARTITION BY total_laid_off
        ORDER BY company
    ) AS company_rank_within_layoff_total
FROM layoffs_staging2
WHERE total_laid_off IS NOT NULL;


-- =========================================================
-- 8. RUNNING TOTAL BY COMPANY
-- =========================================================

-- Aggregate by company and layoff total before calculating the
-- running total. The order here is alphabetical by company.
SELECT
    company,
    total_laid_off,
    SUM(total_laid_off) OVER (
        ORDER BY company, total_laid_off
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total_by_company_order
FROM
(
    SELECT
        company,
        total_laid_off
    FROM layoffs_staging2
    WHERE company IS NOT NULL
      AND total_laid_off IS NOT NULL
    GROUP BY company, total_laid_off
) AS company_layoffs
ORDER BY company, total_laid_off;


-- =========================================================
-- 9. MONTHLY LAYOFFS AND ROLLING TOTAL
-- =========================================================

-- Group by year and month so January from different years is
-- not incorrectly combined with other January records.
WITH monthly_layoffs AS
(
    SELECT
        DATE_FORMAT(`date`, '%Y-%m') AS month,
        SUM(total_laid_off) AS total_off
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
      AND total_laid_off IS NOT NULL
    GROUP BY DATE_FORMAT(`date`, '%Y-%m')
)
SELECT
    month,
    total_off,
    SUM(total_off) OVER (
        ORDER BY month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS rolling_total
FROM monthly_layoffs
ORDER BY month;


-- =========================================================
-- 10. RECORD-LEVEL REVIEW
-- =========================================================

SELECT *
FROM layoffs_staging2;
