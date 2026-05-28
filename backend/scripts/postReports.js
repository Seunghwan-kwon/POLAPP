"use strict";
const url="https://polapp.duckdns.org:444"
async function closeReport(id,cookie){
	const response=await fetch(url+`/reports/${id}/close`,{
		method:"PATCH",
		headers:{
			"Cookie":cookie
		}
	});
	const result=await response.json();
	return result;
}
async function postReport(title,description,severity,latitude,longitude,cookie){
	const response=await fetch(url+"/reports",{
		method:"POST",
		headers:{
			"Content-Type":"application/json",
			"Cookie":cookie
		},
		body:JSON.stringify({
			title,description,
			severity,latitude,longitude
		})
	});
	const result=await response.json();
	return result;
}
async function getReports(status="ALL",cookie=""){
	const response=await fetch(url+`/reports?status=${status}`,{
		headers:{
			"Cookie":cookie
		}
	});
	const result=await response.json();
	return result;
}
async function login(officerId,matchingCode,cookie=""){
	const response=await fetch(url+"/login",{
		method:"POST",
		headers:{
			"Content-Type":"application/json",
			"Cookie":cookie
		},
		body:JSON.stringify({
			officerId,matchingCode
		})
	});
	cookie=response.headers.get("set-cookie");
	const result=await response.json();
	return[result,cookie];
}
async function main(){
	let[result,cookie]=await login("P-1000","abcd1");
	console.log("loginResult",result);
	result=await getReports("OPEN",cookie);
	console.log("getReportsResult",result);
	result=await postReport(
		"test","testDescription",
		"HIGH",1,1,
		cookie
	);
	console.log("postReportsResult",result);
	result=await getReports("OPEN",cookie);
	console.log("getReportsResult",result);
	const report=result.result[0];
	if(report==null){
		console.log("No report");
		return;
	}
	result=await closeReport(report.id,cookie);
	console.log("closeReportResult",result);
	result=await getReports("OPEN",cookie);
	console.log("getReportsResult",result);
}
main();
