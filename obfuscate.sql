-- SQL Script to obfuscate all the text type column from the specified database schema
-- Date : 2024-08-22

-- cat > obfuscate.sql

SET @TABLE_SCHEMA = IFNULL(@TABLE_SCHEMA, 'obfuscated_database'); -- WARNING THIS DATABASE NEED TO EXIST

DROP PROCEDURE IF EXISTS ObfuscateTextColumn;
DELIMITER //
CREATE PROCEDURE ObfuscateTextColumn(IN TABLE_SCHEMA VARCHAR(255))
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE tableName VARCHAR(255);
    DECLARE columnName VARCHAR(255);
    DECLARE cur CURSOR FOR 
        SELECT TABLE_NAME, COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = TABLE_SCHEMA
      AND TABLE_NAME IN ('table1', 'table2', 'table3...') -- HERE ADD THE TABLES THAT YOU WANT TO OBFUSCATE
      AND DATA_TYPE IN ('varchar', 'mediumtext', 'text', 'longtext') -- HERE ADD THE TYPE THAT YOU WANT TO OBFUSCATE
      AND NOT (
        -- HERE ADD THE table.column THAT DON'T WANT TO OBFUSCATE
        (TABLE_NAME = 'table1' AND COLUMN_NAME = 'file_id') 
        OR (TABLE_NAME = 'table1' AND COLUMN_NAME = 'user_uid')
        OR (TABLE_NAME = 'table3' AND COLUMN_NAME = 'url')
        )
      ;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO tableName, columnName;
        IF done THEN
            LEAVE read_loop;
        END IF;

        SET @sql = CONCAT('
            UPDATE ', tableName, '
            SET ', columnName, ' = (
                SELECT SUBSTRING(
                    REPEAT("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc ac luctus mauris. Sed non ex quis leo pretium facilisis. Nam et ante risus. Sed at libero eget purus ultricies porta. Fusce commodo et neque vel luctus. Fusce porta auctor luctus. Ut odio augue, pharetra ac sollicitudin sed, rutrum in orci. Sed auctor urna blandit, lacinia mauris eget, vehicula nulla. Phasellus rutrum tempus lectus, sit amet pharetra urna posuere eu. Sed in tortor non lectus mollis semper ut id nisl. Nam ac ante mi. Vivamus urna ante, vehicula et justo eu, ultrices pellentesque neque. Morbi lacinia et nulla quis accumsan. Aliquam ac tortor non ex euismod auctor eu at neque. Morbi rhoncus eu mauris eget tempor. In hac habitasse platea dictumst. Aenean lectus metus, pellentesque nec mauris eu, semper porttitor lorem. Mauris tincidunt mollis ex tristique placerat. Praesent justo risus, porta a tempor a, euismod sed augue. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae. ", 5),
                    1, 
                    CHAR_LENGTH(', columnName, ')
                )
            );
        ');
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END LOOP;

    CLOSE cur;
END //

DELIMITER ;

SET SQL_SAFE_UPDATES = 0;

-- DELETE SOME TABLE IF DON'T NEEDED IN THE OBFUSCATE DATABASE
SET @sql = CONCAT('DELETE FROM ', (@TABLE_SCHEMA), '.table_unwanted');
PREPARE stmt FROM @sql;EXECUTE stmt;DEALLOCATE PREPARE stmt;

CALL ObfuscateTextColumn(@TABLE_SCHEMA);

SET SQL_SAFE_UPDATES = 1;
