import{PoolConnection}from"mysql2/promise";
import{getDbConnection}from"./db.js";
import SQLHelper from"./SQLHelper.js";
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
	setCode(code:CaseSetCompleteResultCode){
		this.code=code;
	}
	setLogId(logId:number){
		this.logId=logId;
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
	setCode(code:AssignPoliceResultCode){
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
export default class Case{
	static async create(createdBy:number){
	}
	static async getOfficerIds(caseId:number){
		let conn:PoolConnection|null=null;
		let sql:string;
		let result:GetOfficerIdsResult=new GetOfficerIdsResult();
		try{
			conn=await getDbConnection();
			const rows=await SQLHelper.selectAll(
				"select id from tblCasePolice where caseId=?;",
				conn,
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
			if(conn!=null){
				conn.release();
			}
		}
	}
	static async assignPolice(caseId:number,policeId:number,updatedBy:number):Promise<AssignPoliceResult>{
		let conn:PoolConnection|null=null;
		let sql:string;
		let result:AssignPoliceResult=new AssignPoliceResult();
		try{
			conn=await getDbConnection();
			sql="insert into tblCasePolice(caseId,policeId,updatedBy)values(?,?,?);";
			const affectedCount=await SQLHelper.execute(sql,conn,[caseId,policeId,updatedBy]);
			if(affectedCount!=1){
				result.setCode(AssignPoliceResultCode.InsertFailed);
				return result;
			}
			return result;
		}catch(ex){
			result.setCode(AssignPoliceResultCode.Exception1);
			return result;
		}finally{
			if(conn!=null){
				conn.release();
			}
		}
	}
	static async setIncomplete(caseId:number,updatedBy:number){
	}
	static async setComplete(caseId:number,updatedBy:number):Promise<CaseSetCompleteResult>{
		let conn:PoolConnection|null=null;
		let sql:string;
		let result:CaseSetCompleteResult=new CaseSetCompleteResult();
		try{
			conn=await getDbConnection();
			sql="select 1 from tblUser as u inner join tblAdmin as a on u.id=a.userId where u.id=? and u.status=1 limit 1;";
			const hasPermission:number|null=await SQLHelper.selectSingle<number>(sql,conn,[updatedBy]);
			if(hasPermission==null){
				await conn.rollback();
				result.setCode(CaseSetCompleteResultCode.PermissionDenied);
				return result;
			}
			sql="update tblCase set state=200 where id=? and state=0;";
			let affectedCount:number;
			affectedCount=await SQLHelper.execute(sql,conn,[caseId]);
			if(affectedCount!=1){
				await conn.rollback();
				result.setCode(CaseSetCompleteResultCode.CaseUpdateFailed);
				return result;
			}
			sql="insert tblCaseLog(caseId,updatedBy)values(?,?);";
			const logId:number=await SQLHelper.insert(sql,conn,[caseId,updatedBy]);
			if(logId==null){
				await conn.rollback();
				result.setCode(CaseSetCompleteResultCode.LogInsertFailed);
				return result;
			}
			await conn.commit();
			result.setLogId(logId);
			return result;
		}catch(ex1){
			if(conn!=null){
				try{
					await conn.rollback();
					result.setCode(CaseSetCompleteResultCode.Exception1);
					return result;
				}catch(ex2){
					result.setCode(CaseSetCompleteResultCode.Exception2);
					return result;
				}
			}else{
				result.setCode(CaseSetCompleteResultCode.DBConnFailed);
				return result;
			}
		}finally{
			if(conn!=null){
				conn.release();
			}
		}
	}
}
