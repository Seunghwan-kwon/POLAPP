import{PoolConnection}from"mysql2/promise";
import{getDbConnection}from"./db.js";
import SQLHelper from"./SQLHelper.js";
enum RemovePoliceResultCode{
	Success=0,
	Exception1=-1,
	DBConnFailed=-3,
	UpdatePoliceFailed=-4
}
class RemovePoliceResult{
	code:RemovePoliceResultCode;
	constructor(){
		this.code=RemovePoliceResultCode.Success;
	}
	setCode(code:RemovePoliceResultCode){
		this.code=code;
	}
}
enum CreatePoliceResultCode{
	Success=0,
	Exception1=-1,
	DBConnFailed=-3,
	InsertPoliceFailed=-4,
	AlreadyPolice=-5
}
class CreatePoliceResult{
	code:CreatePoliceResultCode;
	policeId:number;
	constructor(){
		this.code=CreatePoliceResultCode.Success;
		this.policeId=-1;
	}
	setCode(code:CreatePoliceResultCode){
		this.code=code;
	}
	setPoliceId(policeId:number){
		this.policeId=policeId;
	}
}
class GetCurrentCaseIdResult{
	code:number;
	caseId:number|null;
	constructor(){
		this.code=0;
		this.caseId=null;
	}
}
class GetPoliceIdResult{
	code:number;
	policeId:number|null;
	constructor(){
		this.code=0;
		this.policeId=null;
	}
}
export default class Police{
	static async getPoliceId(officerId:string):Promise<GetPoliceIdResult>{
		let conn:PoolConnection|null=null;
		const result=new GetPoliceIdResult();
		try{
			conn=await getDbConnection();
			const policeId=await SQLHelper.selectSingle<number>(
				"select id from tblPolice where officerId=? limit 1;",
				conn,
				[officerId]
			);
			result.policeId=policeId;
			return result;
		}catch(err:any){
			result.code=-1;
			return result;
		}finally{
			conn?.release();
		}
	}
	static async getCurrentCaseId(policeId:number):Promise<GetCurrentCaseIdResult>{
		let conn:PoolConnection|null=null;
		const result=new GetCurrentCaseIdResult();
		try{
			conn=await getDbConnection();
			const caseId=await SQLHelper.selectSingle<number>(
				"select caseId from tblPoliceCase where policeId=? limit 1;",
				conn,
				[policeId]
			);
			result.caseId=caseId;
			return result;
		}catch(err:any){
			result.code=-1;
			return result;
		}finally{
			conn?.release();
		}
	}
	static async create(userId:number,officerId:string,createdBy:number):Promise<CreatePoliceResult>{
		let conn:PoolConnection|null=null;
		const result=new CreatePoliceResult();
		try{
			conn=await getDbConnection();
			await conn.beginTransaction();
			const policeId=await SQLHelper.insert(
				"insert into tblPolice(userId,officerId,createdBy)values(?,?,?);",
				conn,
				[userId,officerId,createdBy]
			);
			if(policeId==null){
				await conn.rollback();
				result.code=CreatePoliceResultCode.InsertPoliceFailed;
				return result;
			}
			result.setPoliceId(policeId);
			await conn.commit();
			return result;
		}catch(err:any){
			try{
				await conn?.rollback();
			}catch{}
			if(err?.code==="ER_DUP_ENTRY"){
				result.code=CreatePoliceResultCode.AlreadyPolice;
				return result;
			}
			result.code=CreatePoliceResultCode.Exception1;
			return result;
		}finally{
			conn?.release();
		}
	}
	static async remove(policeId:number,updatedBy:number):Promise<RemovePoliceResult>{
		let conn:PoolConnection|null=null;
		let sql:string;
		const result=new RemovePoliceResult();
		try{
			conn=await getDbConnection();
			await conn.beginTransaction();
			sql="update tblPolice set isActive=0 where id=? and isActive=1;";
			const changedCount=await SQLHelper.execute(sql,conn,[policeId]);
			if(changedCount!==1){
				await conn.rollback();
				result.code=RemovePoliceResultCode.UpdatePoliceFailed;
				return result;
			}
			await conn.commit();
			return result;
		}catch(ex1){
			try{
				await conn?.rollback();
			}catch{}
			result.code=RemovePoliceResultCode.Exception1;
			return result;
		}finally{
			conn?.release();
		}
	}
}
