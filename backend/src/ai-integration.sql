CREATE TABLE IF NOT EXISTS tblThreatAlert(
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	eventId VARCHAR(200) NOT NULL,
	officerId INT NOT NULL,
	sessionId VARCHAR(120) NULL,
	category VARCHAR(80) NOT NULL,
	alertLabel VARCHAR(80) NOT NULL,
	riskLevel TINYINT UNSIGNED NOT NULL,
	evidenceIndex DECIMAL(6,2) NOT NULL DEFAULT 0,
	reasonsJson TEXT NOT NULL,
	latitude DOUBLE NULL,
	longitude DOUBLE NULL,
	occurredAt DATETIME(3) NOT NULL,
	createdAt DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
	PRIMARY KEY(id),
	UNIQUE KEY uqThreatAlertEventId(eventId),
	KEY ixThreatAlertOfficerTime(officerId,occurredAt),
	KEY ixThreatAlertRiskTime(riskLevel,occurredAt)
)ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
