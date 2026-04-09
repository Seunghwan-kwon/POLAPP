import mysql,{Pool,PoolConnection}from"mysql2/promise";
const pool:Pool=mysql.createPool({
	host:process.env.dbHost||"",
	user:process.env.dbUser||"",
	database:process.env.database||"",
	password:process.env.password||""
});
export async function getDbConnection():Promise<PoolConnection>{
	return await pool.getConnection();
}
