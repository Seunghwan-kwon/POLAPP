import bcrypt from"bcrypt";
import DBConnection from"./DBConnection.js";
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
}
interface UserRow{
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
}
export default class User{
	static async remove(conn:DBConnection,userId:number,updatedBy:number):Promise<UserRemoveResult>{
		const result=new UserRemoveResult();
		try{
			await conn.beginTransaction();
			const historyId=await conn.insert(
				"insert into tblUserHistory(userId,email,passwordHash)select id,email,passwordHash from tblUser where id=? limit 1;",
				[userId]
			);
			if(historyId==null){
				await conn.rollback();
				result.code=UserRemoveResultCode.HistoryInsertFailed;
				return result;
			}
			const changedCount=await conn.update(
				"delete from tblUser where id=?;",
				[userId]
			);
			if(changedCount!==1){
				await conn.rollback();
				result.code=UserRemoveResultCode.DeleteFailed;
				return result;
			}
			await conn.commit();
			return result;
		}catch(ex1){
			try{
				await conn?.rollback();
			}catch{}
			result.code=UserRemoveResultCode.Exception1;
			return result;
		}finally{
			conn?.release();
		}
	}
	static async login(conn:DBConnection,email:string,password:string):Promise<UserLoginResult>{
		const result=new UserLoginResult();
		try{
			const userRow=await conn.selectRow<UserRow>(
				"select id,passwordHash from tblUser where email=? and isActive=1 limit 1;",
				[email]
			);
			if(userRow==null){
				await conn.rollback();
				result.code=UserLoginResultCode.NoSuchUser;
				return result;
			}
			const passwordMatched=await bcrypt.compare(password,userRow.passwordHash);
			if(!passwordMatched){
				await conn.rollback();
				result.code=UserLoginResultCode.PasswordMismatch;
				return result;
			}
			const insertId=await conn.insert(
				"insert into tblLoginLog(userId,method)values(?,1);",
				[userRow.id]
			);
			if(insertId==null){
				await conn.rollback();
				result.code=UserLoginResultCode.LogInsertFailed;
				return result;
			}
			result.userId=userRow.id;
			await conn.commit();
			return result;
		}catch(ex1){
			try{
				await conn?.rollback();
			}catch{}
			result.code=UserLoginResultCode.Exception1;
			return result;
		}finally{
			conn?.release();
		}
	}
	static async create(conn:DBConnection,email:string,password:string,createdBy:number,name:string):Promise<UserCreateResult>{
		const result=new UserCreateResult();
		try{
			await conn.beginTransaction();
			const passwordHash=await bcrypt.hash(password,12);
			const userId=await conn.insert(
				"insert into tblUser(email,passwordHash,createdBy)values(?,?,?);",
				[email,passwordHash,createdBy]
			);
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
			result.code=UserCreateResultCode.Exception1;
			return result;
		}finally{
			conn?.release();
		}
	}
}
