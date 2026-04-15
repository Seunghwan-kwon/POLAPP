type QueryParam=string|number|boolean|null|Date;
export type QueryParams=QueryParam[];
export default class DBConnection{
	insert(sql:string,params:QueryParams=[]):Promise<number>{
		return new Promise(function(resolve){resolve(-1);});
	}
	update(sql:string,params:QueryParams=[]):Promise<number>{
		return new Promise(function(resolve){resolve(-1);});
	}
	selectSingle<T>(sql:string,params:QueryParams=[]):Promise<T|null>{
		return new Promise(function(resolve){resolve(null);});
	}
	selectRow<T>(sql:string,params:QueryParams=[]):Promise<T|null>{
		return new Promise(function(resolve){resolve(null);});
	}
	selectAll<T>(sql:string,params:QueryParams=[]):Promise<T[]>{
		return new Promise(function(resolve){resolve(new Array<T>());});
	}
	beginTransaction():Promise<void>{
		return new Promise(function(resolve){resolve(undefined);});
	}
	commit():Promise<void>{
		return new Promise(function(resolve){resolve(undefined);});
	}
	rollback():Promise<void>{
		return new Promise(function(resolve){resolve(undefined);});
	}
	release(){
	}
}
