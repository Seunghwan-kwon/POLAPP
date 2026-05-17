import DBConnection from"./DBConnection.js";
import Officer from"./Officer.js";
export default class Role{
	id:number;
	code:string;
	officers:Map<number,Officer>;
	constructor(id:number,code:string){
		this.id=id;
		this.code=code;
		this.officers=new Map<number,Officer>();
	}
	addOfficer(officer:Officer){
		this.officers.set(officer.id,officer);
	}
	removeOfficer(officer:Officer){
		this.officers.delete(officer.id);
	}
	static cached=new Map<number,Role|null>();
	static async getCached(id:number,code:string,conn:DBConnection):Promise<Role|null>{
		let role=Role.cached.get(id);
		if(role===undefined){
			const code=await conn.selectSingle<string>("select code from tblRole where id=? limit 1;",[id]);
			if(code==null){
				Role.cached.set(id,null);
				return null;
			}else{
				role=new Role(id,code);
				Role.cached.set(id,role);
			}
		}
		return role;
	}
	static async findByCode(code:string,conn:DBConnection):Promise<Role|null>{
		const id=await conn.selectSingle<number>("select id from tblRole where code=? limit 1;",[code]);
		if(id==null){
			return null;
		}
		return await Role.getCached(id,code,conn);
	}
}
