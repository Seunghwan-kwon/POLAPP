import Officer from"./Officer.js";
import DBConnection from"./DBConnection.js";
import{getDateStr}from"./Utils.js";
export default class Region{
	id:number;
	code:string;
	officers:Map<number,Officer>;
	constructor(id:number,code:string){
		this.id=id;
		this.code=code;
		this.officers=new Map<number,Officer>();
	}
	addOfficer(officer:Officer):void{
		this.officers.set(officer.id,officer);
		console.log(`[${getDateStr()}] [Region.addOfficer] code=${this.code},officer.code=${officer.code},size=${this.officers.size}`);
	}
	removeOfficer(officer:Officer):void{
		this.officers.delete(officer.id);
	}
	static cached=new Map<number,Region|null>();
	static async getCached(id:number,conn:DBConnection):Promise<Region|null>{
		let region=Region.cached.get(id);
		if(region===undefined){
			const code=await conn.selectSingle<string>("select code from tblRegion where id=? limit 1;",[id]);
			if(code==null){
				Region.cached.set(id,null);
				return null;
			}else{
				region=new Region(id,code);
				Region.cached.set(id,region);
			}
		}
		return region;
	}
	static async findByCode(code:string,conn:DBConnection):Promise<Region|null>{
		const id=await conn.selectSingle<number>("select id from tblRegion where code=? limit 1;",[code]);
		if(id==null){
			return null;
		}
		return await Region.getCached(id,conn);
	}
}
