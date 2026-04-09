import{PoolConnection,ResultSetHeader,RowDataPacket}from"mysql2/promise";
type QueryParams=(string|number|boolean|null|Date)[];
export default class SQLHelper{
	static async insert(sql:string,conn:PoolConnection,params:QueryParams):Promise<number>{
		const[result]=await conn.execute<ResultSetHeader>(sql,params);
		return result.insertId;
	}
	static async selectAll<T extends RowDataPacket>(sql:string,conn:PoolConnection,params:QueryParams):Promise<T[]>{
		const[rows]=await conn.execute<RowDataPacket[]>(sql,params);
		return rows as T[];
	}
	static async selectSingle<T>(sql:string,conn:PoolConnection,params:QueryParams):Promise<T|null>{
		const[rows]=await conn.execute<RowDataPacket[]>(sql,params);
		if(rows.length==0){
			return null;
		}
		const row=rows[0];
		const value=Object.values(row)[0];
		return value;
	}
	static async selectRow<T extends RowDataPacket>(sql:string,conn:PoolConnection,params:QueryParams):Promise<T|null>{
		const[rows]=await conn.execute<RowDataPacket[]>(sql,params);
		if(rows.length==0){
			return null;
		}
		const row=rows[0];
		return row as T;
	}
	static async execute(sql:string,conn:PoolConnection,params:QueryParams):Promise<number>{
		const[result]=await conn.execute<ResultSetHeader>(sql,params);
		return result.changedRows;
	}
}
