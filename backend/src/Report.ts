import DBConnection from"./DBConnection.js";
enum ReportCloseResultCode{
	Success=0,
	Exception1=-1,
	Exception2=-2,
	LogInsertFailed=-3,
	UpdateFailed=-4,
	PermissionDenied=-5,
	DBConnFailed=-6
}
class ReportCloseResult{
	code:ReportCloseResultCode;
	constructor(code:ReportCloseResultCode){
		this.code=code;
	}
}
export enum GetOfficerIdsResultCode{
	Success=0,
	Exception1=-1,
}
class GetOfficerIdsResult{
	ids:number[];
	code:number;
	constructor(){
		this.ids=new Array<number>()
		this.code=GetOfficerIdsResultCode.Success;
	}
}
export default class Report{
	id:number;
	title:string;
	description:string;
	severity:string;
	latitude:number;
	longitude:number;
	status:string;
	createdBy:number;
	createdAt:string;
	closedBy:number|null;
	closedAt:string|null;
	constructor(
		id:number,title:string,description:string,severity:string,
		latitude:number,longitude:number,status:string,
		createdBy:number,createdAt:string,
		closedBy:number|null,closedAt:string|null
	){
		this.id=id;
		this.title=title;
		this.description=description;
		this.severity=severity;
		this.latitude=latitude;
		this.longitude=longitude;
		this.status=status;
		this.createdBy=createdBy;
		this.createdAt=createdAt;
		this.closedBy=closedBy;
		this.closedAt=closedAt;
	}
	static cached=new Map<number,Report|null>();
	static async getCached(id:number,conn:DBConnection):Promise<Report|null>{
		let report=Report.cached.get(id);
		if(report==undefined){
			const row=await conn.selectRow<any>(
				"select id,title,description,severity,status,longitude,latitude,createdBy,createdAt,closedAt from tblReport where id=? limit 1;",
				[id]
			);
			if(row==null){
				Report.cached.set(id,null);
				return null;
			}
			const title=row[1];
			const description=row[2];
			const severity=row[3];
			const status=row[4];
			const longitude=Number(row[5]);
			const latitude=Number(row[6]);
			const createdBy=Number(row[7]);
			const createdAt=String(row[8]);
			const closedBy=Number(row[9]);
			const closedAt=String(row[10]);
			report=new Report(
				id,title,description,severity,
				longitude,latitude,status,
				createdBy,createdAt,closedBy,closedAt
			);
			Report.cached.set(id,report);
		}
		return report;
	}
	static async create(
		title:string,description:string,
		severity:string,
		latitude:number,longitude:number,
		status:string|null,createdBy:number,createdAt:string,
		closedBy:number|null,closedAt:string|null,
		conn:DBConnection
	):Promise<Report|null>{
		try{
			if(status==null){
				status="OPEN";
			}
			const insertId=await conn.insert(
				"insert into tblReport(title,description,severity,latitude,longitude,status,createdBy,createdAt,closedBy,closedAt)values(?,?,?,?,?,?,?,?,?,?);",
				[
					title,description,severity,
					latitude,longitude,status,
					createdBy,new Date(),
					closedBy,closedAt
				]
			);
			if(insertId==null){
				return null;
			}
			const report=new Report(
				insertId,title,description,severity,
				latitude,longitude,status,
				createdBy,createdAt,closedBy,closedAt
			);
			Report.cached.set(insertId,report);
			return report; 
		}catch(ex){
			console.error(ex);
			return null;
		}
	}
	static async select(conn:DBConnection,status:string|null):Promise<number[]|null>{
		const ids=[];
		try{
			let rows;
			if(status==null||status==="ALL"){
				rows=await conn.selectAll<any>(
					"select id from tblReport;",
					[]
				);
			}else{
				rows=await conn.selectAll<any>(
					"select id from tblReport where status=?;",
					[status]
				);
			}
			for(const row of rows){
				ids.push(row["id"]);
			}
			return ids;
		}catch(ex){
			console.error(ex);
			return null;
		}finally{
		}
	}
	/*
	static async getOfficerIds(conn:DBConnection,caseId:number){
		const result=new GetOfficerIdsResult();
		try{
			const rows=await conn.selectAll<any>(
				"select id from tblCaseOfficer where caseId=?;",
				[caseId]
			);
			for(const row of rows){
				result.ids.push(row["id"]);
			}
			return result;
		}catch(ex){
			result.code=GetOfficerIdsResultCode.Exception1;
			return result;
		}finally{
		}
	}
       */
      	/*
	async assignOfficer(officerId:number,updatedBy:number,conn:DBConnection):Promise<AssignOfficerResult>{
		try{
			const insertId=await conn.insert(
				"insert into tblCaseOfficer(caseId,policeId,updatedBy)values(?,?,?);",
				[this.id,officerId,updatedBy]
			);
			if(insertId==null){
				return new AssignOfficerResult(
					AssignOfficerResultCode.InsertFailed
				);
			}
			return new AssignOfficerResult(
				AssignOfficerResultCode.Success
			);
		}catch(ex){
			return new AssignOfficerResult(
				AssignOfficerResultCode.Exception1
			);
		}finally{
		}
	}
       	*/
       	/*
	async setIncomplete(updatedBy:number){
	}
       	*/
	async hasPermission(updater:number,conn:DBConnection):Promise<boolean>{
		const hasPermission=await conn.selectSingle<number>(
			"select 1 from tblUser as u inner join tblAdmin as a on u.id=a.userId where u.id=? and u.status=1 limit 1;",
			[updater]
		);
		return hasPermission!=null;
	}
	async setStatus(status:string,conn:DBConnection):Promise<number>{
		const changedCount=await conn.update(
			"update tblReport set status=? where id=? and status=?;",
			[status,this.id,this.status]
		);
		if(changedCount==1){
			this.status=status;
		}
		return changedCount;
	}
	async close(closedBy:number,conn:DBConnection):Promise<ReportCloseResult>{
		try{
			await conn.beginTransaction();
			const changedCount=await this.setStatus("CLOSED",conn);

			if(changedCount!=1){
				await conn.rollback();
				return new ReportCloseResult(
					ReportCloseResultCode.UpdateFailed
				);
			}
			await conn.commit();
			return new ReportCloseResult(
				ReportCloseResultCode.Success
			);
		}catch(ex1){
			console.error(ex1);
			try{
				await conn.rollback();
			}catch{}
			return new ReportCloseResult(
				ReportCloseResultCode.Exception1,
			);
		}finally{
		}
	}
}
