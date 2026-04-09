use polapp;
create table tblUser(
	id bigint auto_increment primary key,
	email varchar(64)not null,
	passwordHash varchar(64)not null,
	createdBy bigint not null,
	createdAt datetime not null default current_timestamp,
	unique key uq_tblUser_email(email)
);
create table tblPolice(
	id bigint auto_increment primary key,
	userId bigint not null,
	isActive int not null default 1,
	createdBy bigint not null,
	createdAt datetime not null default current_timestamp,
	updatedBy bigint not null,
	updatedAt datetime not null default current_timestamp,
	unique key uq_tblUser_userId(userId)
);
create table tblPoliceHistory(
	id bigint auto_increment primary key,
	policeId bigint not null,
	unique key uq_tblPoliceHistory_policeId(policeId)
);
create table tblCase(
	id bigint auto_increment primary key,
	name varchar(32)not null,
	createdBy bigint not null,
	createdAt datetime not null default current_timestamp,
	updatedBy bigint not null,
	updatedAt datetime not null default current_timestamp
);
create table tblCasePolice(
	id bigint auto_increment primary key,
	caseId bigint not null,
	policeId bigint not null,
	createdBy bigint not null,
	createdAt datetime not null default current_timestamp,
	unique key uq_tblCasePolice_caseId_policeId(caseId,policeId)
);
