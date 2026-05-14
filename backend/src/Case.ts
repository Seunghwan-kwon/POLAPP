import DBConnection from"./DBConnection.js";
enum CaseSetCompleteResultCode{
	Success=0,
	Exception1=-1,
	Exception2=-2,
	LogInsertFailed=-3,
	UpdateFailed=-4,
	PermissionDenied=-5,
	DBConnFailed=-6
}
class CaseSetCompleteResult{
	code:CaseSetCompleteResultCode;
	logId:number;
	constructor(code:CaseSetCompleteResultCode,logId:number){
		this.code=code;
		this.logId=logId;
	}
}
enum AssignOfficerResultCode{
	Success=0,
	Exception1=-1,
	InsertFailed=-2,
}
class AssignOfficerResult{
	code:AssignOfficerResultCode;
	constructor(code:AssignOfficerResultCode){
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
	id:number;
	state:number;
	conn:DBConnection;
	constructor(id:number,conn:DBConnection){
		this.id=id;
		this.conn=conn;
		this.state=-1;
	}
	static cached=new Map<number,Case|null>();
	static async getCached(id:number,conn:DBConnection):Promise<Case|null>{
		let _case=Case.cached.get(id);
		if(_case===undefined){
			const row=await conn.selectRow<any>(
				"select id from tblCase where caseId=? limit 1;",
				[id]
			);
			if(row==null){
				Case.cached.set(id,null);
				return null;
			}
			_case=new Case(id,conn);
			Case.cached.set(id,_case);
		}
		return _case;
	}
	static async create(name:string,createdBy:number,conn:DBConnection):Promise<Case|null>{
		try{
			const insertId=await conn.insert(
				"insert into tblCase(name,createdBy)values(?,?);",
				[name,createdBy]
			);
			if(insertId==null){
				return null;
			}
			const _case=new Case(insertId,conn);
			Case.cached.set(insertId,_case);
			return _case;
		}catch(ex){
			console.error(ex);
			return null;
		}
	}
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
	async assignOfficer(officerId:number,updatedBy:number):Promise<AssignOfficerResult>{
		try{
			const insertId=await this.conn.insert(
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
	async setIncomplete(updatedBy:number){
	}
	async hasPermission(updater:number):Promise<boolean>{
		const hasPermission=await this.conn.selectSingle<number>(
			"select 1 from tblUser as u inner join tblAdmin as a on u.id=a.userId where u.id=? and u.status=1 limit 1;",
			[updater]
		);
		return hasPermission!=null;
	}
	async setState(state:number):Promise<number>{
		const changedCount=await this.conn.update(
			"update tblCase set state=? where id=? and state=?;",
			[state,this.id,this.state]
		);
		return changedCount;
	}
	async setComplete(updatedBy:number):Promise<CaseSetCompleteResult>{
		try{
			const hasPermission=await this.conn.selectSingle<number>(
				"select 1 from tblUser as u inner join tblAdmin as a on u.id=a.userId where u.id=? and u.status=1 limit 1;",
				[updatedBy]
			);
			if(!await this.hasPermission(updatedBy)){
				await this.conn.rollback();
				return new CaseSetCompleteResult(
					CaseSetCompleteResultCode.PermissionDenied,
					-1
				);
			}
			const changedCount=await this.setState(200);

			if(changedCount!=1){
				await this.conn.rollback();
				return new CaseSetCompleteResult(
					CaseSetCompleteResultCode.UpdateFailed,
					-1
				);
			}
			const logId=await this.conn.insert(
				"insert tblCaseLog(caseId,updatedBy)values(?,?);",
				[this.id,updatedBy]
			);
			if(logId==null){
				await this.conn.rollback();
				return new CaseSetCompleteResult(
					CaseSetCompleteResultCode.LogInsertFailed,
					-1
				);
			}
			await this.conn.commit();
			return new CaseSetCompleteResult(
				CaseSetCompleteResultCode.LogInsertFailed,
				logId
			);
		}catch(ex1){
			try{
				await this.conn.rollback();
			}catch{}
			return new CaseSetCompleteResult(
				CaseSetCompleteResultCode.Exception1,
				-1
			);
		}finally{
		}
	}
}
