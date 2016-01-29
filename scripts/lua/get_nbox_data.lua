--
-- (C) 2013-15 - ntop.org
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

require "lua_utils"

local json = require ("dkjson")

interface.select(ifname)

local nbox_host = ntop.getCache("ntopng.prefs.nbox_host")
local nbox_user = ntop.getCache("ntopng.prefs.nbox_user")
local nbox_password = ntop.getCache("ntopng.prefs.nbox_password")
if((nbox_host == nil) or (nbox_host == "")) then nbox_host = "localhost" end
if((nbox_user == nil) or (nbox_user == "")) then nbox_user = "nbox" end
if((nbox_password == nil) or (nbox_password == "")) then nbox_password = "nbox" end

local base_url = "https://"..nbox_host

local status_url = base_url.."/ntop-bin/check_status_tasks_external.cgi"
local schedule_url = base_url.."/ntop-bin/sudowrapper_external.cgi?script=npcapextract_external.cgi"
local activity_scheduler_url = base_url.."/ntop-bin/config_scheduler.cgi"
local download_url = base_url.."/ntop-bin/sudowrapper.cgi"
download_url = download_url.."?script=n2disk_filemanager.cgi&opt=download_pcap&dir=/storage/n2disk/&pcap_name=/storage/n2disk/"


-- Query parameters
action       = _GET["action"]
epoch_begin  = _GET["epoch_begin"]
epoch_end    = _GET["epoch_end"]
host         = _GET["host"]
l4proto      = _GET["l4proto"]
port         = _GET["port"]
task_id      = _GET["task_id"]



function createBPF()
	local bpf = ""
	if host ~= nil and host ~= "" then bpf = "src or dst host "..host end
	if port ~= nil and port ~= "" then if bpf ~= "" then bpf = bpf.." and " end bpf = bpf.."port "..port end
	if l4proto ~= nil and l4proto ~= "" then if bpf ~= "" then bpf = bpf.." and " end bpf = bpf.."ip proto "..l4proto end
	if bpf ~= "" then return "&bpf="..bpf else return "" end
end

if action == nil then
	return "{}"
elseif action == "schedule" then
	schedule_url = schedule_url.."&ifname="..ifname.."&begin="..epoch_begin.."&end="..epoch_end
	schedule_url = schedule_url..createBPF()
	--io.write(schedule_url..'\n')
	local resp = ntop.httpGet(schedule_url, nbox_user, nbox_password, 10)
	-- tprint(resp)
	sendHTTPHeader('text/html; charset=iso-8859-1')
	if resp ~= nil and resp["CONTENT"] ~= nil then
		print(resp["CONTENT"])
	else
		print("{}")
	end
elseif action == "status" then
	-- datatable parameters
	local current_page = _GET["currentPage"]
	local per_page     = _GET["perPage"]
	local sort_column  = _GET["sortColumn"]
	local sort_order   = _GET["sortOrder"]

	if sort_column == nil or sort_column == "column_" then
		sort_column = getDefaultTableSort("pcaps")
	else
		if sort_column ~= "column_" and sort_column ~= "" then
			tablePreferences("sort_pcaps", sort_column)
		end
	end

	if sort_order == nil then
		sort_order = getDefaultTableSortOrder("pcaps")
	else
		if sort_column ~= "column_" and sort_column ~= "" then
			tablePreferences("sort_order_pcaps", sort_order)
		end
	end
	if sort_order == "asc" then
		funct = asc
	else
		funct = rev
	end

	if current_page == nil then
		current_page = 1
	else
		current_page = tonumber(current_page)
	end

	if per_page == nil then
		per_page = getDefaultTableSize()
	else
		per_page = tonumber(per_page)
		tablePreferences("rows_number", per_page)
	end
	local to_skip = (current_page - 1) * per_page
	if to_skip < 0 then to_skip = 0 end

	sendHTTPHeader('text/html; charset=iso-8859-1')
	local resp = ntop.httpGet(status_url, nbox_user, nbox_password, 10)
	if resp ~= nil and resp["CONTENT"] ~= nil then
		local content = resp["CONTENT"]
		-- resp is not valid json: is buggy @ 08-01-2016:
		-- this is an example { "result" : "OK", "tasks" : { {"task_id" : "1_1452012196" , "status" : "done" } , {"task_id" : "1_1452012274" , "status" : "done" }}}
		-- double {{ and }} are not allowed and we must convert them to [{ and }] respectively
		content = string.gsub(content, "%s*","")
		content = string.gsub(content, "{%s*{","[{")
		content = string.gsub(content, "}%s*}","}]")
		content = json.decode(content, 1, nil)
		if content == nil or content["tasks"] == nil then
			print('{"data":[]}')
		else
			local tasks = {}
			for _,task in pairs(content["tasks"]) do
				if task["status"] ~= "scheduled" then
					task["actions"] = 
					'<a href="'..download_url..task["task_id"]..'.pcap"><i class="fa fa-download fa-lg"></i></a> '
				end
				task["actions"] = task["actions"]..'<a href="'..activity_scheduler_url..'" target="_blank"><i class="fa fa-external-link fa-lg"></i></a> '
				tasks[task["task_id"]] =
				{["column_task_id"] = task["task_id"], ["column_status"] = task["status"], ["column_actions"] = task["actions"]}
			end
			local sorter = {}
			for task_id, task in pairs(tasks) do
				if sort_column == "column_task_id" then sorter[task_id] = task_id
				elseif sort_column == "column_status" then sorter[task_id] = task["column_status"]
				elseif sort_column == "column_actions" then sorter[task_id] = task["column_actions"]
				else sorter[task_id] = task_id end
			end
			local num_page = 0
			local total_rows = 0
			local result_data = {}
			for task_id,_ in pairsByValues(sorter, funct) do
				if to_skip > 0 then
					to_skip = to_skip - 1
				elseif num_page < per_page then
					table.insert(result_data, tasks[task_id])
					num_page = num_page + 1
				end
				total_rows = total_rows + 1
			end
			local result = {}
			result["perPage"] = per_page
			result["currentPage"] = current_page
			result["totalRows"] = total_rows
			result["data"] = result_data
			result["sort"] = {{sort_column, sort_order}}
			print(json.encode(result, nil))
		end

	else
		print('{"data":[]}')
	end
else
	print("{}")
end

