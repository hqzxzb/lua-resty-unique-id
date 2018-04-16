--生成唯一ID

--格式：13位毫秒级时间戳-12位IP地址-6位Nginx Worker PID-3位Nginx Worker号-6位自增随机数

--Nginx日志写入
local log = ngx.log;

unique_id = {
	version = "1.0.0";
	ip = "";
	worker = {};
};

--Split string by separator
local function splitThis(s, sp)
	local res = {};

    local temp = s;
    local len = 0;
    while true do
        len = string.find(temp, sp);
        if len ~= nil then
            local result = string.sub(temp, 1, len-1);
            temp = string.sub(temp, len+1);
            table.insert(res, result);
        else
            table.insert(res, temp);
            break;
        end
    end

    return res;
end

--Get Nginx Timestamps for milliseconds
local function ngxNow()
	ngx.update_time();
	local time = ngx.now();
	local tmp = splitThis(time, "%.");
	if(tmp[2] == nil) then
		table.insert(tmp, 2, "0");
	end
	return tmp[1]..string.gsub(string.format("%03s", tmp[2]), "%s", "0");
end

--判断操作系统类型，区分Linux与Windows
local function getOS()
	local envHOME = os.getenv("HOME");
	if(envHOME ~= nil and string.match(envHOME, "/")) then
		return "Linux";
	end

	local envOS = os.getenv("OS");
	if(envOS ~= nil and string.match(envOS, "[Ww]indows")) then
		return "Windows";
	end

	return "unkown";
end


--获取服务器12位IP，去除"."用0补足12位
local function get12IP()
	local osName = getOS();
	log(ngx.INFO, "Unique ID OS : ", osName);
	local ip = "";

	if(osName == "Linux") then
		local z = io.popen("ifconfig | grep 'inet addr' | awk '{ print $2}' | awk -F: '{print $2}'");
		local x = z:read("*all");
		local key = string.gmatch(x, "(%d+%.%d+%.%d+%.%d+)");
		for i in key do
			if(i ~= "127.0.0.1" and i ~= "192.168.0.1" and i ~= "192.168.1.1") then
				ip = i;
				break;
			end
		end
		
		if(ip == "") then
			local z1 = io.popen("hostname -i");
			local x1 = z1:read("*all");
			local key1 = string.gmatch(x1, "(%d+%.%d+%.%d+%.%d+)");
			for i in key1 do
				if(i ~= "127.0.0.1" and i ~= "192.168.0.1" and i ~= "192.168.1.1") then
					ip = i;
					break;
				end
			end
		end
	elseif(osName == "Windows") then
		local t = io.popen("ipconfig |find /i \"ipv4\"");
		local a = t:read("*all");
		local key = string.gmatch(a, "(%d+%.%d+%.%d+%.%d+)");
		for i in key do
			if(i ~= "127.0.0.1" and i ~= "192.168.0.1" and i ~= "192.168.1.1") then
				ip = i;
				break;
			end
		end
	end
	if(ip == "") then
		log(ngx.INFO, "Unique ID IP not found, create random ip, '9' + 11bit time string reverse");
		ngx.update_time();
	    ip = '9'..string.gsub(ngxNow(), "%.", ""):reverse():sub(1, 11);
	end
	
	if(string.match(ip, "%.")) then
		local tmp = splitThis(ip, "%.");
		ip = "";
		for key, value in ipairs(tmp) do
			ip = ip..string.format("%03s", value);
		end
	end

	return string.gsub(ip, '%s', '0');
end


--初始化
function unique_id.init()
	local ip = get12IP();
	log(ngx.INFO, "Unique ID 12IP : ", ip);
	unique_id.ip = ip;
	log(ngx.INFO, "Unique ID init complete !");
end

--生成唯一ID
function unique_id.id()
	--生成时间戳
	ngx.update_time();
	local timeNow = string.gsub(ngxNow(), "%.", "");
	
	--生成worker pid
	local workerPID = ngx.worker.pid();
	local workerPIDStr = string.gsub(string.format("%06s", tostring(workerPID)), "%s", "0");
	
	--生成worker id
	local workerID = ngx.worker.id();
	local workerIDStr = string.gsub(string.format("%03s", tostring(workerID)), "%s", "0");
	
	--生成自增数
	local increment = "";
	
	local key = "worker"..workerID;
    
    log(ngx.DEBUG, "worker key : ", key);
    local workerThis = unique_id.worker[key];
    
	if(workerThis ~= nil) then
    	log(ngx.DEBUG, "worker id cache : ", workerThis.num, ":", workerThis.time);
		if(workerThis.num < 10000) then
			workerThis.num = workerThis.num + 1;
		else
			workerThis.num = 0;
		end
		workerThis.time = timeNow;
	else
		log(ngx.DEBUG, "worker id cache is nil");
		unique_id.worker[key] = {
			num = 0;
			time = timeNow;
		};
		workerThis = unique_id.worker[key];
	end
	increment = string.gsub(string.format("%06s", tostring(workerThis.num)), "%s", "0");
	
	return timeNow.."-"..unique_id.ip.."-"..workerPIDStr.."-"..workerIDStr.."-"..increment;
end
