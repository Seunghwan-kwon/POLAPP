import DBConnection,{QueryParams}from"./DBConnection.js";
import mysql,{Pool,PoolConnection,ResultSetHeader,RowDataPacket}from"mysql2/promise";
const pool:Pool=mysql.createPool({
	host:process.env.dbHost||"",
	user:process.env.dbUser||"",
	database:process.env.database||"",
	password:process.env.password||""
});
export class MySqlConnection extends DBConnection{
	conn:PoolConnection;
	constructor(conn:PoolConnection){
		super();
		this.conn=conn;
	}
	async insert(sql:string,params:QueryParams=[]):Promise<number>{
		const[result]=await this.conn.execute<ResultSetHeader>(sql,params);
		return result.insertId;
	}
	async update(sql:string,params:QueryParams):Promise<number>{
		const[result]=await this.conn.execute<ResultSetHeader>(sql,params);
		return result.changedRows;
	}
	async selectSingle<T>(sql:string,params:QueryParams):Promise<T|null>{
		const[rows]=await this.conn.execute<RowDataPacket[]>(sql,params);
		if(rows.length==0){
			return null;
		}
		const row=rows[0];
		const value=Object.values(row)[0];
		return value as T;
	}
	async selectRow<T>(sql:string,params:QueryParams):Promise<T|null>{
		const[rows]=await this.conn.execute<RowDataPacket[]>(sql,params);
		if(rows.length==0){
			return null;
		}
		const row=rows[0];
		const values=Object.values(row);
		return values as T;
	}
	async selectAll<T>(sql:string,params:QueryParams=[]):Promise<T[]>{
		const[rows]=await this.conn.execute<RowDataPacket[]>(sql,params);
		return rows as T[];
	}
	async beginTransaction():Promise<void>{
		await this.conn.beginTransaction();
	}
	async commit():Promise<void>{
		await this.conn.commit();
	}
	async rollback():Promise<void>{
		await this.conn.rollback();
	}
	release(){
		this.conn.release();
	}
}
export async function getMySqlConnection():Promise<MySqlConnection>{
	const conn=await pool.getConnection();
	return new MySqlConnection(conn);
}
