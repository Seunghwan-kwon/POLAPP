import bcrypt from"bcrypt";
import{PoolConnection,RowDataPacket}from"mysql2/promise";
import{getDbConnection}from"./db.js";
import SQLHelper from"./SQLHelper.js";
enum UserCreateResultCode{
	Success=0,
	Exception1=-1,
	Exception2=-2,
	DBConnFailed=-3,
}
class UserCreateResult{
	code:UserCreateResultCode;
	userId:number|null;
	constructor(){
		this.code=UserCreateResultCode.Success;
		this.userId=null;
	}
	setCode(code:UserCreateResultCode){
		this.code=code;
	}
}
enum UserLoginResultCode{
	Success=0,
	Exception1=-1,
	Exception2=-2,
	DBConnFailed=-3,
	PasswordMismatch=-4,
	LogInsertFailed=-5,
	NoSuchUser=-6
}
class UserLoginResult{
	code:UserLoginResultCode;
	userId:number|null;
	constructor(){
		this.code=UserLoginResultCode.Success;
		this.userId=null;
	}
	setCode(code:UserLoginResultCode){
		this.code=code;
	}
}
interface UserRow extends RowDataPacket{
	id:number,
	passwordHash:string
}
enum UserRemoveResultCode{
	Success=0,
	Exception1=-1,
	HistoryInsertFailed=-2,
	DeleteFailed=-3,
}
class UserRemoveResult{
	code:UserRemoveResultCode;
	constructor(){
		this.code=UserRemoveResultCode.Success;
	}
	setCode(code:UserRemoveResultCode){
		this.code=code;
	}
}
export default class User{
	static async remove(userId:number,updatedBy:number):Promise<UserRemoveResult>{
		let conn:PoolConnection|null=null;
		const result=new UserRemoveResult();
		try{
			conn=await getDbConnection();
			await conn.beginTransaction();
			const historyId=await SQLHelper.insert(
				"insert into tblUserHistory(userId,email,passwordHash)select id,email,passwordHash from tblUser where id=? limit 1;",
				conn,
				[userId]
			);
			if(historyId==null){
				await conn.rollback();
				result.setCode(UserRemoveResultCode.HistoryInsertFailed);
				return result;
			}
			const changedCount=await SQLHelper.execute(
				"delete from tblUser where id=?;",
				conn,
				[userId]
			);
			if(changedCount!==1){
				await conn.rollback();
				result.setCode(UserRemoveResultCode.DeleteFailed);
				return result;
			}
			await conn.commit();
			return result;
		}catch(ex1){
			try{
				await conn?.rollback();
			}catch{}
			result.setCode(UserRemoveResultCode.Exception1);
			return result;
		}finally{
			conn?.release();
		}
	}
	static async login(email:string,password:string):Promise<UserLoginResult>{
		let conn:PoolConnection|null=null;
		let sql:string;
		let result=new UserLoginResult();
		try{
			conn=await getDbConnection();
			sql="select id,passwordHash from tblUser where email=? and isActive=1 limit 1;";
			const userRow=await SQLHelper.selectRow<UserRow>(sql,conn,[email]);
			if(userRow==null){
				await conn.rollback();
				result.setCode(UserLoginResultCode.NoSuchUser);
				return result;
			}
			const passwordMatched=await bcrypt.compare(password,userRow.passwordHash);
			if(!passwordMatched){
				await conn.rollback();
				result.setCode(UserLoginResultCode.PasswordMismatch);
				return result;
			}
			sql="insert into tblLoginLog(userId,method)values(?,1);";
			const insertId:number|null=await SQLHelper.insert(sql,conn,[userRow.id]);
			if(insertId==null){
				await conn.rollback();
				result.setCode(UserLoginResultCode.LogInsertFailed);
				return result;
			}
			result.userId=userRow.id;
			await conn.commit();
			return result;
		}catch(ex1){
			try{
				await conn?.rollback();
			}catch{}
			result.setCode(UserLoginResultCode.Exception1);
			return result;
		}finally{
			conn?.release();
		}
	}
	static async create(email:string,password:string,createdBy:number,name:string):Promise<UserCreateResult>{
		const result:UserCreateResult=new UserCreateResult();
		let conn:PoolConnection|null=null;
		let sql:string;
		try{
			conn=await getDbConnection();
			await conn.beginTransaction();
			const passwordHash=await bcrypt.hash(password,12);
			sql="insert into tblUser(email,passwordHash,createdBy)values(?,?,?);";
			const userId:number=await SQLHelper.insert(sql,conn,[email,passwordHash,createdBy]);
			if(userId==null){
				await conn.rollback();
				return result;
			}
			result.userId=userId;
			await conn.commit();
			return result;
		}catch(ex1){
			try{
				await conn?.rollback();
			}catch{}
			result.setCode(UserCreateResultCode.Exception1);
			return result;
		}finally{
			conn?.release();
		}
	}
}
