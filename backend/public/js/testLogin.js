"use strict";
window.addEventListener("error",(e)=>{
	contentElement.innerText="오류 발생 "+e.toString();
});
const idBox=document.createElement("input");
idBox.type="text";
idBox.value="P-1000";
document.body.appendChild(idBox);
const codeBox=document.createElement("input");
codeBox.type="text";
codeBox.value="aa0001";
document.body.appendChild(codeBox);
const submitElement=document.createElement("div");
{
	const e=submitElement;
	e.innerText="로그인";
}
document.body.appendChild(submitElement);
let contentElement;
const outputPanel=document.createElement("div");
{
	const e=outputPanel;
	e.style.marginTop="20px";
	e.style.border="1px solid #000";
	e.style.paddingTop="20px";
	e.style.paddingBottom="20px";
	const titleElement=document.createElement("div");
	{
		const e=titleElement;
		e.innerText="Response Body";
	}
	e.appendChild(titleElement);
	contentElement=document.createElement("div");
	{
	}
	e.appendChild(contentElement);
}
document.body.appendChild(outputPanel);
submitElement.addEventListener("click",async()=>{
	try{
		const response=await fetch("/login",{
			method:"POST",
			body:JSON.stringify({
				officerId:idBox.value,
				matchingCode:codeBox.value
			}),
			headers:{
				"Content-Type":"application/json"
			}
		});
		const resultJson=await response.json();
		contentElement.innerText=JSON.stringify(resultJson);
	}catch(e){
		console.error(e.toString());
		contentElement.innerText=e.toString();
	}
});
