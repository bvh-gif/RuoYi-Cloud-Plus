-- MySQL dump 10.13  Distrib 8.4.9, for Linux (x86_64)
--
-- Host: localhost    Database: nacos
-- ------------------------------------------------------
-- Server version	8.4.9

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `ai_resource`
--

DROP TABLE IF EXISTS `ai_resource`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ai_resource` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'id',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'åˆ›å»ºæ—¶é—´',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'ä¿®æ”¹æ—¶é—´',
  `name` varchar(256) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'èµ„æºåç§°',
  `type` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'èµ„æºç±»åž‹',
  `c_desc` varchar(2048) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'èµ„æºæè¿°',
  `status` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'èµ„æºçŠ¶æ€',
  `namespace_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT 'å‘½åç©ºé—´ID',
  `biz_tags` varchar(1024) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'ä¸šåŠ¡æ ‡ç­¾',
  `ext` longtext COLLATE utf8mb4_unicode_ci COMMENT 'æ‰©å±•ä¿¡æ¯(JSON)',
  `c_from` varchar(256) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'local' COMMENT 'æ¥æºæ ‡è¯†(å¯¼å…¥/åŒæ­¥æ¥æº)',
  `version_info` longtext COLLATE utf8mb4_unicode_ci COMMENT 'ç‰ˆæœ¬ä¿¡æ¯(JSON)',
  `meta_version` bigint NOT NULL DEFAULT '1' COMMENT 'å…ƒæ•°æ®ç‰ˆæœ¬(ä¹è§‚é”)',
  `scope` varchar(16) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'PRIVATE' COMMENT 'å¯è§æ€§: PUBLIC/PRIVATE',
  `owner` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT 'åˆ›å»ºè€…ç”¨æˆ·å',
  `download_count` bigint NOT NULL DEFAULT '0' COMMENT 'ä¸‹è½½æ¬¡æ•°',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_ai_resource_ns_name_type` (`namespace_id`,`name`,`type`,`c_from`),
  KEY `idx_ai_resource_name` (`name`),
  KEY `idx_ai_resource_type` (`type`),
  KEY `idx_ai_resource_gmt_modified` (`gmt_modified`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AIèµ„æºå…ƒæ•°æ®è¡¨';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ai_resource`
--

LOCK TABLES `ai_resource` WRITE;
/*!40000 ALTER TABLE `ai_resource` DISABLE KEYS */;
/*!40000 ALTER TABLE `ai_resource` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ai_resource_version`
--

DROP TABLE IF EXISTS `ai_resource_version`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ai_resource_version` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'id',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'åˆ›å»ºæ—¶é—´',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'ä¿®æ”¹æ—¶é—´',
  `type` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'èµ„æºç±»åž‹',
  `author` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'ä½œè€…',
  `name` varchar(256) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'èµ„æºåç§°',
  `c_desc` varchar(2048) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'ç‰ˆæœ¬æè¿°',
  `status` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'ç‰ˆæœ¬çŠ¶æ€',
  `version` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'ç‰ˆæœ¬å·',
  `namespace_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT 'å‘½åç©ºé—´ID',
  `storage` longtext COLLATE utf8mb4_unicode_ci COMMENT 'å­˜å‚¨ä¿¡æ¯(JSON)',
  `publish_pipeline_info` longtext COLLATE utf8mb4_unicode_ci COMMENT 'å‘å¸ƒæµæ°´çº¿ä¿¡æ¯(JSON)',
  `download_count` bigint NOT NULL DEFAULT '0' COMMENT 'ä¸‹è½½æ¬¡æ•°',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_ai_resource_ver_ns_name_type_ver` (`namespace_id`,`name`,`type`,`version`),
  KEY `idx_ai_resource_ver_name` (`name`),
  KEY `idx_ai_resource_ver_status` (`status`),
  KEY `idx_ai_resource_ver_gmt_modified` (`gmt_modified`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AIèµ„æºç‰ˆæœ¬è¡¨';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ai_resource_version`
--

LOCK TABLES `ai_resource_version` WRITE;
/*!40000 ALTER TABLE `ai_resource_version` DISABLE KEYS */;
/*!40000 ALTER TABLE `ai_resource_version` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `config_info`
--

DROP TABLE IF EXISTS `config_info`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `config_info` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'id',
  `data_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'data_id',
  `group_id` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'group_id',
  `content` longtext COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'content',
  `md5` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'md5',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'åˆ›å»ºæ—¶é—´',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'ä¿®æ”¹æ—¶é—´',
  `src_user` text COLLATE utf8mb4_unicode_ci COMMENT 'source user',
  `src_ip` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'source ip',
  `app_name` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'app_name',
  `tenant_id` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT 'ç§Ÿæˆ·å­—æ®µ',
  `c_desc` varchar(256) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'configuration description',
  `c_use` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'configuration usage',
  `effect` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'é…ç½®ç”Ÿæ•ˆçš„æè¿°',
  `type` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'é…ç½®çš„ç±»åž‹',
  `c_schema` text COLLATE utf8mb4_unicode_ci COMMENT 'é…ç½®çš„æ¨¡å¼',
  `encrypted_data_key` varchar(1024) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT 'å¯†é’¥',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_configinfo_datagrouptenant` (`data_id`,`group_id`,`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='config_info';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `config_info`
--

LOCK TABLES `config_info` WRITE;
/*!40000 ALTER TABLE `config_info` DISABLE KEYS */;
/*!40000 ALTER TABLE `config_info` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `config_info_gray`
--

DROP TABLE IF EXISTS `config_info_gray`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `config_info_gray` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT 'id',
  `data_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'data_id',
  `group_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'group_id',
  `content` longtext COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'content',
  `md5` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'md5',
  `src_user` text COLLATE utf8mb4_unicode_ci COMMENT 'src_user',
  `src_ip` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'src_ip',
  `gmt_create` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT 'gmt_create',
  `gmt_modified` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT 'gmt_modified',
  `app_name` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'app_name',
  `tenant_id` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT 'tenant_id',
  `gray_name` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'gray_name',
  `gray_rule` text COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'gray_rule',
  `encrypted_data_key` varchar(256) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT 'encrypted_data_key',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_configinfogray_datagrouptenantgray` (`data_id`,`group_id`,`tenant_id`,`gray_name`),
  KEY `idx_dataid_gmt_modified` (`data_id`,`gmt_modified`),
  KEY `idx_gmt_modified` (`gmt_modified`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='config_info_gray';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `config_info_gray`
--

LOCK TABLES `config_info_gray` WRITE;
/*!40000 ALTER TABLE `config_info_gray` DISABLE KEYS */;
/*!40000 ALTER TABLE `config_info_gray` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `config_tags_relation`
--

DROP TABLE IF EXISTS `config_tags_relation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `config_tags_relation` (
  `id` bigint NOT NULL COMMENT 'id',
  `tag_name` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'tag_name',
  `tag_type` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'tag_type',
  `data_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'data_id',
  `group_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'group_id',
  `tenant_id` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT 'tenant_id',
  `nid` bigint NOT NULL AUTO_INCREMENT COMMENT 'nid, è‡ªå¢žé•¿æ ‡è¯†',
  PRIMARY KEY (`nid`),
  UNIQUE KEY `uk_configtagrelation_configidtag` (`id`,`tag_name`,`tag_type`),
  KEY `idx_tenant_id` (`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='config_tag_relation';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `config_tags_relation`
--

LOCK TABLES `config_tags_relation` WRITE;
/*!40000 ALTER TABLE `config_tags_relation` DISABLE KEYS */;
/*!40000 ALTER TABLE `config_tags_relation` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `group_capacity`
--

DROP TABLE IF EXISTS `group_capacity`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `group_capacity` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT 'ä¸»é”®ID',
  `group_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT 'Group IDï¼Œç©ºå­—ç¬¦è¡¨ç¤ºæ•´ä¸ªé›†ç¾¤',
  `quota` int unsigned NOT NULL DEFAULT '0' COMMENT 'é…é¢ï¼Œ0è¡¨ç¤ºä½¿ç”¨é»˜è®¤å€¼',
  `usage` int unsigned NOT NULL DEFAULT '0' COMMENT 'ä½¿ç”¨é‡',
  `max_size` int unsigned NOT NULL DEFAULT '0' COMMENT 'å•ä¸ªé…ç½®å¤§å°ä¸Šé™ï¼Œå•ä½ä¸ºå­—èŠ‚ï¼Œ0è¡¨ç¤ºä½¿ç”¨é»˜è®¤å€¼',
  `max_aggr_count` int unsigned NOT NULL DEFAULT '0' COMMENT 'èšåˆå­é…ç½®æœ€å¤§ä¸ªæ•°ï¼Œï¼Œ0è¡¨ç¤ºä½¿ç”¨é»˜è®¤å€¼',
  `max_aggr_size` int unsigned NOT NULL DEFAULT '0' COMMENT 'å•ä¸ªèšåˆæ•°æ®çš„å­é…ç½®å¤§å°ä¸Šé™ï¼Œå•ä½ä¸ºå­—èŠ‚ï¼Œ0è¡¨ç¤ºä½¿ç”¨é»˜è®¤å€¼',
  `max_history_count` int unsigned NOT NULL DEFAULT '0' COMMENT 'æœ€å¤§å˜æ›´åŽ†å²æ•°é‡',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'åˆ›å»ºæ—¶é—´',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'ä¿®æ”¹æ—¶é—´',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_group_id` (`group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='é›†ç¾¤ã€å„Groupå®¹é‡ä¿¡æ¯è¡¨';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `group_capacity`
--

LOCK TABLES `group_capacity` WRITE;
/*!40000 ALTER TABLE `group_capacity` DISABLE KEYS */;
/*!40000 ALTER TABLE `group_capacity` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `his_config_info`
--

DROP TABLE IF EXISTS `his_config_info`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `his_config_info` (
  `id` bigint unsigned NOT NULL COMMENT 'id',
  `nid` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT 'nid, è‡ªå¢žæ ‡è¯†',
  `data_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'data_id',
  `group_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'group_id',
  `app_name` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'app_name',
  `content` longtext COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'content',
  `md5` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'md5',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'åˆ›å»ºæ—¶é—´',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'ä¿®æ”¹æ—¶é—´',
  `src_user` text COLLATE utf8mb4_unicode_ci COMMENT 'source user',
  `src_ip` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'source ip',
  `op_type` char(10) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'operation type',
  `tenant_id` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT 'ç§Ÿæˆ·å­—æ®µ',
  `encrypted_data_key` varchar(1024) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT 'å¯†é’¥',
  `publish_type` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT 'formal' COMMENT 'publish type gray or formal',
  `gray_name` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'gray name',
  `ext_info` longtext COLLATE utf8mb4_unicode_ci COMMENT 'ext info',
  PRIMARY KEY (`nid`),
  KEY `idx_gmt_create` (`gmt_create`),
  KEY `idx_gmt_modified` (`gmt_modified`),
  KEY `idx_did` (`data_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='å¤šç§Ÿæˆ·æ”¹é€ ';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `his_config_info`
--

LOCK TABLES `his_config_info` WRITE;
/*!40000 ALTER TABLE `his_config_info` DISABLE KEYS */;
/*!40000 ALTER TABLE `his_config_info` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `permissions`
--

DROP TABLE IF EXISTS `permissions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `permissions` (
  `role` varchar(50) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'role',
  `resource` varchar(128) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'resource',
  `action` varchar(8) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'action',
  UNIQUE KEY `uk_role_permission` (`role`,`resource`,`action`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `permissions`
--

LOCK TABLES `permissions` WRITE;
/*!40000 ALTER TABLE `permissions` DISABLE KEYS */;
/*!40000 ALTER TABLE `permissions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `pipeline_execution`
--

DROP TABLE IF EXISTS `pipeline_execution`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pipeline_execution` (
  `execution_id` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'æ‰§è¡ŒID',
  `resource_type` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'èµ„æºç±»åž‹',
  `resource_name` varchar(256) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'èµ„æºåç§°',
  `namespace_id` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'å‘½åç©ºé—´ID',
  `version` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'ç‰ˆæœ¬',
  `status` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'æ‰§è¡ŒçŠ¶æ€',
  `pipeline` longtext COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'pipelineèŠ‚ç‚¹ç»“æžœJSON',
  `create_time` bigint NOT NULL COMMENT 'åˆ›å»ºæ—¶é—´',
  `update_time` bigint NOT NULL COMMENT 'ä¿®æ”¹æ—¶é—´',
  PRIMARY KEY (`execution_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AIèµ„æºå‘å¸ƒå®¡æ ¸Pipelineæ‰§è¡Œè®°å½•';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `pipeline_execution`
--

LOCK TABLES `pipeline_execution` WRITE;
/*!40000 ALTER TABLE `pipeline_execution` DISABLE KEYS */;
/*!40000 ALTER TABLE `pipeline_execution` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `roles`
--

DROP TABLE IF EXISTS `roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `roles` (
  `username` varchar(50) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'username',
  `role` varchar(50) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'role',
  UNIQUE KEY `idx_user_role` (`username`,`role`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `roles`
--

LOCK TABLES `roles` WRITE;
/*!40000 ALTER TABLE `roles` DISABLE KEYS */;
/*!40000 ALTER TABLE `roles` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `tenant_capacity`
--

DROP TABLE IF EXISTS `tenant_capacity`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `tenant_capacity` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT 'ä¸»é”®ID',
  `tenant_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT 'Tenant ID',
  `quota` int unsigned NOT NULL DEFAULT '0' COMMENT 'é…é¢ï¼Œ0è¡¨ç¤ºä½¿ç”¨é»˜è®¤å€¼',
  `usage` int unsigned NOT NULL DEFAULT '0' COMMENT 'ä½¿ç”¨é‡',
  `max_size` int unsigned NOT NULL DEFAULT '0' COMMENT 'å•ä¸ªé…ç½®å¤§å°ä¸Šé™ï¼Œå•ä½ä¸ºå­—èŠ‚ï¼Œ0è¡¨ç¤ºä½¿ç”¨é»˜è®¤å€¼',
  `max_aggr_count` int unsigned NOT NULL DEFAULT '0' COMMENT 'èšåˆå­é…ç½®æœ€å¤§ä¸ªæ•°',
  `max_aggr_size` int unsigned NOT NULL DEFAULT '0' COMMENT 'å•ä¸ªèšåˆæ•°æ®çš„å­é…ç½®å¤§å°ä¸Šé™ï¼Œå•ä½ä¸ºå­—èŠ‚ï¼Œ0è¡¨ç¤ºä½¿ç”¨é»˜è®¤å€¼',
  `max_history_count` int unsigned NOT NULL DEFAULT '0' COMMENT 'æœ€å¤§å˜æ›´åŽ†å²æ•°é‡',
  `gmt_create` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'åˆ›å»ºæ—¶é—´',
  `gmt_modified` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'ä¿®æ”¹æ—¶é—´',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_tenant_id` (`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='ç§Ÿæˆ·å®¹é‡ä¿¡æ¯è¡¨';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `tenant_capacity`
--

LOCK TABLES `tenant_capacity` WRITE;
/*!40000 ALTER TABLE `tenant_capacity` DISABLE KEYS */;
/*!40000 ALTER TABLE `tenant_capacity` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `tenant_info`
--

DROP TABLE IF EXISTS `tenant_info`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `tenant_info` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT 'id',
  `kp` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'kp',
  `tenant_id` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT 'tenant_id',
  `tenant_name` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT 'tenant_name',
  `tenant_desc` varchar(256) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'tenant_desc',
  `create_source` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'create_source',
  `gmt_create` bigint NOT NULL COMMENT 'åˆ›å»ºæ—¶é—´',
  `gmt_modified` bigint NOT NULL COMMENT 'ä¿®æ”¹æ—¶é—´',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_tenant_info_kptenantid` (`kp`,`tenant_id`),
  KEY `idx_tenant_id` (`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='tenant_info';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `tenant_info`
--

LOCK TABLES `tenant_info` WRITE;
/*!40000 ALTER TABLE `tenant_info` DISABLE KEYS */;
/*!40000 ALTER TABLE `tenant_info` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `username` varchar(50) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'username',
  `password` varchar(500) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'password',
  `enabled` tinyint(1) NOT NULL COMMENT 'enabled',
  PRIMARY KEY (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-08-31 16:05:06
