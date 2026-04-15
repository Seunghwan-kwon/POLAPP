import DBConnection from"./DBConnection.js";
enum CaseSetCompleteResultCode{
	Success=0,
	Exception1=-1,
	Exception2=-2,
	LogInsertFailed=-3,
	CaseUpdateFailed=-4,
	PermissionDenied=-5,
	DBConnFailed=-6
}
class CaseSetCompleteResult{
	code:CaseSetCompleteResultCode;
	logId:number;
	constructor(){
		this.code=CaseSetCompleteResultCode.Success;
		this.logId=-1;
	}
}
enum AssignPoliceResultCode{
	Success=0,
	Exception1=-1,
	InsertFailed=-2,
}
class AssignPoliceResult{
	code:AssignPoliceResultCode;
	constructor(){
		this.code=AssignPoliceResultCode.Success;
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
export default class Case{
	static async create(createdBy:number){
	}
	static async getOfficerIds(conn:DBConnection,caseId:number){
		const result=new GetOfficerIdsResult();
		try{
			const rows=await conn.selectAll<any>(
				"select id from tblCasePolice where caseId=?;",
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
			conn?.release();
		}
	}
	static async assignPolice(conn:DBConnection,caseId:number,policeId:number,updatedBy:number):Promise<AssignPoliceResult>{
		const result=new AssignPoliceResult();
		try{
			const insertId=await conn.insert(
				"insert into tblCasePolice(caseId,policeId,updatedBy)values(?,?,?);",
				[caseId,policeId,updatedBy]
			);
			if(insertId==null){
				result.code=AssignPoliceResultCode.InsertFailed;
				return result;
			}
			return result;
		}catch(ex){
			result.code=AssignPoliceResultCode.Exception1;
			return result;
		}finally{
			conn?.release();
		}
	}
	static async setIncomplete(caseId:number,updatedBy:number){
	}
	static async setComplete(conn:DBConnection,caseId:number,updatedBy:number):Promise<CaseSetCompleteResult>{
		const result=new CaseSetCompleteResult();
		try{
			const hasPermission=await conn.selectSingle<number>(
				"select 1 from tblUser as u inner join tblAdmin as a on u.id=a.userId where u.id=? and u.status=1 limit 1;",
				[updatedBy]
			);
			if(hasPermission==null){
				await conn.rollback();
				result.code=CaseSetCompleteResultCode.PermissionDenied;
				return result;
			}
			const affectedCount=await conn.update(
				"update tblCase set state=200 where id=? and state=0;",
				[caseId]
			);
			if(affectedCount!=1){
				await conn.rollback();
				result.code=CaseSetCompleteResultCode.CaseUpdateFailed;
				return result;
			}
			const logId=await conn.insert(
				"insert tblCaseLog(caseId,updatedBy)values(?,?);",
				[caseId,updatedBy]
			);
			if(logId==null){
				await conn.rollback();
				result.code=CaseSetCompleteResultCode.LogInsertFailed;
				return result;
			}
			await conn.commit();
			result.logId=logId;
			return result;
		}catch(ex1){
			try{
				await conn.rollback();
			}catch{}
			result.code=CaseSetCompleteResultCode.Exception1;
			return result;
		}finally{
			conn?.release();
		}
	}
}
