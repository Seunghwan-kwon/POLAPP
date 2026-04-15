import DBConnection from"./DBConnection.js";
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
	static async getPoliceId(conn:DBConnection,officerId:string):Promise<GetPoliceIdResult>{
		const result=new GetPoliceIdResult();
		try{
			const policeId=await conn.selectSingle<number>(
				"select id from tblPolice where officerId=? limit 1;",
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
	static async getCurrentCaseId(conn:DBConnection,policeId:number):Promise<GetCurrentCaseIdResult>{
		const result=new GetCurrentCaseIdResult();
		try{
			const caseId=await conn.selectSingle<number>(
				"select caseId from tblPoliceCase where policeId=? limit 1;",
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
	static async create(conn:DBConnection,userId:number,officerId:string,createdBy:number):Promise<CreatePoliceResult>{
		const result=new CreatePoliceResult();
		try{
			await conn.beginTransaction();
			const policeId=await conn.insert(
				"insert into tblPolice(userId,officerId,createdBy)values(?,?,?);",
				[userId,officerId,createdBy]
			);
			if(policeId==null){
				await conn.rollback();
				result.code=CreatePoliceResultCode.InsertPoliceFailed;
				return result;
			}
			result.policeId=policeId;
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
	static async remove(conn:DBConnection,policeId:number,updatedBy:number):Promise<RemovePoliceResult>{
		const result=new RemovePoliceResult();
		try{
			await conn.beginTransaction();
			const changedCount=await conn.update(
				"update tblPolice set isActive=0 where id=? and isActive=1;",
				[policeId]
			);
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
