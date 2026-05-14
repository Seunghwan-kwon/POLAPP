-- MySQL dump 10.17  Distrib 10.3.14-MariaDB, for CYGWIN (x86_64)
--
-- Host: localhost    Database: polapp
-- ------------------------------------------------------
-- Server version	10.3.14-MariaDB

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `tblOfficer`
--

DROP TABLE IF EXISTS `tblOfficer`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `tblOfficer` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `code` varchar(24) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `tblOfficer`
--

LOCK TABLES `tblOfficer` WRITE;
/*!40000 ALTER TABLE `tblOfficer` DISABLE KEYS */;
INSERT INTO `tblOfficer` VALUES (1,'P-0001'),(2,'P-0002');
/*!40000 ALTER TABLE `tblOfficer` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `tblRegion`
--

DROP TABLE IF EXISTS `tblRegion`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `tblRegion` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `code` varchar(24) NOT NULL DEFAULT 'DEFAULT',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `tblRegion`
--

LOCK TABLES `tblRegion` WRITE;
/*!40000 ALTER TABLE `tblRegion` DISABLE KEYS */;
INSERT INTO `tblRegion` VALUES (1,'DEFAULT');
/*!40000 ALTER TABLE `tblRegion` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `tblRole`
--

DROP TABLE IF EXISTS `tblRole`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `tblRole` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `code` varchar(24) NOT NULL DEFAULT 'NONE',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `tblRole`
--

LOCK TABLES `tblRole` WRITE;
/*!40000 ALTER TABLE `tblRole` DISABLE KEYS */;
INSERT INTO `tblRole` VALUES (1,'ADMIN'),(2,'NONE');
/*!40000 ALTER TABLE `tblRole` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-05-14 15:11:28
