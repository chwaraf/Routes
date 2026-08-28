----------------------------------
--[[
Ant Colony Optimization (ACO) for Travelling Salesman Problem (TSP)
for Routes (a World of Warcraft addon)

Copyright (C) 2011 Xinhuan

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA.
]]

---------------------------------
--[[
Ant Colony Optimization and the Travelling Salesman Problem

The Travelling Salesman Problem (TSP) consists of finding the shortest tour
between n cities visiting each once only and ending at the starting point. Let
d(i,j) be the distance between cities i and j and t(i,j) the amount of pheromone
on the edge that connects i and j. t(i,j) is initially set to a small value
t(0), the same for all edges (i,j). The algorithm consists of a series of
iterations.

One iteration of the simplest ACO algorithm applied to the TSP can be summarized
as follows: (1) a set of m artificial ants are initially located at randomly
selected cities; (2) each ant, denoted by k, constructs a complete tour,
visiting each city exactly once, always maintaining a list J(k) of cities that
remain to be visited; (3) an ant located at city i hops to a city j, selected
among the cities that have not yet been visited, according to probability
p(k,i,j) = (t(i,j)^a * d(i,j)^-b) / sum(t(i,l)^a * d(i,l)^-b, all l in J(k))
where a and b are two positive parameters which govern the respective influences
of pheromone and distance; (4) when every ant has completed a tour, pheromone
trails are updated: t(i,j) = (1-p) * t(i,j) + D(t(i,j)), where p is the
evaporation rate and D(t(i,j)) is the amount of reinforcement received by edge
(i,j). D(t(i,j)) is proportional to the quality of the solutions in which (i,j)
was used by one ant or more. More precisely, if L(k) is the length of the tour
T(k) constructed by ant k, then D(t(i,j)) = sum(D(t(k,i,j)), 1 to m) with
D(t(k,i,j)) = Q / L(k) if (i,j) is in T(k) and D(t(k,i,j)) = 0 otherwise, where
Q is a positive parameter. This reinforcement procedure reflects the idea that
pheromone density should be lower on a longer path because a longer trail is
more difficult to maintain.

Steps (1) to (4) are repeated either a predefined number of times or until a
satisfactory solution has been found. The algorithm works by reinforcing
portions of solutions that belong to good solutions and by applying a
dissipation mechanism, pheromone evaporation, which ensures that the system does
not converge early toward a poor solution. When a = 0, the algorithm implements
a probabilistic greedy search, whereby the next city is selected solely on the
basis of its distance from the current city. When b = 0, only the pheromone is
used to guide the search, which would react the way the ants do it. However, the
explicit use of distance as a criterion for path selection appears to improve
the algorithm's performance. In all other optimization applications also, an
improvement in the algorithm's performance is observed when a local measure of
greed, similar to the inverse of distance for the TSP, is included into the
local selection of portions of solution by the agents. Typical parameter values
are: m = n, a = 1, b = 5, p = 0.5, t(0) = 1e-6.

-- Inspiration for optimization from social insect behaviour
-- by E. Bonabeau, M. Dorigo & G. Theraulaz
-- NATURE, VOL 406, 6 JULY 2000, www.nature.com
]]

-- Note:
-- The functions in this file are written specifically for use with Routes
-- in mind and is not a general TSP library.

----------------------------------
-- Localize some globals
local ipairs, pairs, type = ipairs, pairs, type
local random = random
local floor, ceil = floor, ceil
local coroutine = coroutine
local tinsert, tremove = tinsert, tremove
local debugprofilestop = debugprofilestop
local debugprofilestart = debugprofilestart
local math_max = math.max
local inf = math.huge
local exp = math.exp
local log = math.log

local pathR = {}
local lastpath
local Routes = LibStub("AceAddon-3.0"):GetAddon("Routes")
local TSP = {}
Routes.TSP = TSP


--------------------------------
-- Background execution

local nextYield = 0
local function yield()
	local t = debugprofilestop()
	if t > nextYield then
		nextYield = t + 30
		coroutine.yield()
	elseif t < nextYield then
		-- Someone called debugprofilestart(), we need to reset our timer, yield anyway
		nextYield = t + 30
		coroutine.yield()
	end
end


-----------------------------------------------------
-- Function to get the intersection point of 2 lines (x1,y1)-(x2,y2) and (sx,sy)-(ex,ey)
--[[ Unused function, its inlined in SolveTSP()
function TSP:GetIntersection(x1, y1, x2, y2, sx, sy, ex, ey)
	local dx = x2-x1
	local dy = y2-y1
	local numer = dx*(sy-y1) - dy*(sx-x1)
	local demon = dx*(sy-ey) + dy*(ex-sx)
	if demon == 0 or dx == 0 then
		return false
	else
		local u = numer / demon
		local t = (sx + (ex-sx)*u - x1)/dx
		if u >= 0 and u <= 1 and t >= 0 and t <= 1 then
			--return sx + (ex-sx)*u, sy + (ey-sy)*u -- coordinate of intersection
			return true
		end
	end
end]]


-----------------------------------------------------
-- Coroutine code to allow background pathing

local TSPUpdateFrame = CreateFrame("Frame")
TSPUpdateFrame.running = false

function TSPUpdateFrame:OnUpdate(elapsed)
	local status, path, meta, shortestPathLength, count, timetaken = coroutine.resume(self.co)
	if status then
		if coroutine.status(self.co) == "dead" then
			-- Function finished, return results
			self:SetScript("OnUpdate", nil)
			self.running = false
			self.finishFunc(path, meta, shortestPathLength, count, timetaken)
			self.finishFunc = nil
			self.statusFunc = nil
			self.co = nil
			self.nodes = nil
		end
	else
		-- An error occured in the coroutine, abort and print the error
		self:SetScript("OnUpdate", nil)
		self.running = false
		self.co = nil
		self.finishFunc = nil
		self.statusFunc = nil
		self.nodes = nil
		Routes:Print(Routes.L["The following error occured in the background path generation coroutine, please report to Grum or Xinhuan:"])
		Routes:Print(path)
	end
end

local TSPClusterFrame = CreateFrame("Frame")
TSPClusterFrame.running = false

function TSPClusterFrame:OnUpdate(elapsed)
	local status, nodes, metadata, pathLength = coroutine.resume(self.co)
	if status then
		if coroutine.status(self.co) == "dead" then
			-- Function finished, return results
			self:SetScript("OnUpdate", nil)
			self.running = false
			self.finishFunc(nodes, metadata, pathLength)
			self.finishFunc = nil
			self.statusFunc = nil
			self.co = nil
			self.nodes = nil
		end
	else
		-- An error occured in the coroutine, abort and print the error
		self:SetScript("OnUpdate", nil)
		self.running = false
		self.co = nil
		self.finishFunc = nil
		self.statusFunc = nil
		self.nodes = nil
		Routes:Print(Routes.L["The following error occured in the background clustering coroutine, please report to Grum or Xinhuan:"])
		Routes:Print(nodes)
	end
end

-- True while ANY background job (pathing or clustering) is running, with the
-- route table it is working on. Both job types read the route at start and
-- overwrite it at finish, so only one may run at a time (see
-- SolveTSPBackground / ClusterRouteBackground) - this is what lets the
-- delete/edit guards below refuse to touch a busy route.
function TSP:IsTSPRunning()
	if TSPUpdateFrame.running then
		return true, TSPUpdateFrame.nodes
	end
	if TSPClusterFrame.running then
		return true, TSPClusterFrame.nodes
	end
	return nil
end

-- Same arguments as TSP:SolveTSP(), without the "nonblocking" argument
function TSP:SolveTSPBackground(nodes, metadata, taboos, zoneID, parameters, path)
	if not TSPUpdateFrame.running and not TSPClusterFrame.running then
		TSPUpdateFrame.co = coroutine.create(TSP.SolveTSP)
		TSPUpdateFrame:SetScript("OnUpdate", TSPUpdateFrame.OnUpdate)
		TSPUpdateFrame.running = true
		TSPUpdateFrame.nodes = nodes
		local status = coroutine.resume(TSPUpdateFrame.co, TSP, nodes, metadata, taboos, zoneID, parameters, path, true)
		if status then
			-- Do nothing, path isn't complete because at least 1 yield() is called.
			return 1
		else
			-- An error occured in the coroutine, abort and return the error message.
			TSPUpdateFrame.running = false
			TSPUpdateFrame:SetScript("OnUpdate", nil)
			TSPUpdateFrame.co = nil
			return 3, path
		end
	else
		-- There is already a TSP or clustering job running
		return 2
	end
end

function TSP:SetFinishFunction(func)
	assert(type(func) == "function", "SetFinishFunction() expected function in 1st argument, got "..type(func).." instead.")
	TSPUpdateFrame.finishFunc = func
end

function TSP:SetStatusFunction(func)
	assert(type(func) == "function", "SetStatusFunction() expected function in 1st argument, got "..type(func).." instead.")
	TSPUpdateFrame.statusFunc = func
end


-----------------------------------
-- TSP:SolveTSP(nodes, metadata, taboos, zoneID, parameters, path, nonblocking)
-- Dispatches to the solver named by parameters.algorithm. Both solvers take the
-- same arguments and return the same values, so callers (including the
-- background coroutine) do not care which one runs.
--   "aco" - Ant Colony Optimization + 2-opt. The original solver.
--   "ils" - Iterated Local Search (2-opt + Or-opt over k-nearest candidate
--           lists, double-bridge kicks). Default.
function TSP:SolveTSP(nodes, metadata, taboos, zoneID, parameters, path, nonblocking)
	if parameters and parameters.algorithm == "aco" then
		return TSP:SolveTSPACO(nodes, metadata, taboos, zoneID, parameters, path, nonblocking)
	end
	return TSP:SolveTSPILS(nodes, metadata, taboos, zoneID, parameters, path, nonblocking)
end


-----------------------------------
-- TSP:SolveTSPACO(nodes, metadata, zoneID, parameters, path, nonblocking)
-- Arguments
--   nodes       - The table containing a list of Routes node IDs to path
--                 This list should only contain nodes on the same map. This
--                 table should be indexed numerically from nodes[1] to nodes[n].
--   metadata    - The table containing the cluster metadata, if available
--   taboos      - A table containing a table of taboo regions to use.
--   zoneID      - The map area ID of the map that the route is to be generated on.
--   parameters  - The table containing the ACO parameters to use.
--   path        - An optional input table that is used to supply the result
--                 table. If this is nil, the function returns a new table.
--   nonblocking - A boolean to indicate whether the function should yield() regularly.
-- Returns
--   path        - The result TSP path is a table indexed numerically from path[1]
--                 to path[n], a list of Routes node IDs.
--   metadata    - The table containing the cluster metadata, if available
--   length      - The length in yards of the path returned.
--   iteration   - Number of interations taken.
--   timeTaken   - Number of seconds used.
-- Notes: A new nodes[] and metadata[] table is returned. The original tables
--        sent in are unmodified.
function TSP:SolveTSPACO(nodes, metadata, taboos, zoneID, parameters, path, nonblocking)
	-- Notes: Some of these code might look convoluted, with seemingly unnecessary use of too many locals
	-- and make the code look longer. But they are for speed optimization.
	assert(type(nodes) == "table", "SolveTSP() expected table in 1st argument, got "..type(nodes).." instead.")
	assert(type(taboos) == "table", "SolveTSP() expected table in 3rd argument, got "..type(taboos).." instead.")
	assert(type(parameters) == "table", "SolveTSP() expected table in 5th argument, got "..type(parameters).." instead.")
	if type(path) == "table" then
		wipe(path)
	else
		path = {}
	end

	if nonblocking then
		-- Ensure that at least 1 yield() is called in a nonblocking call
		coroutine.yield()
	end

	-- Check for trivial problem of 3 or less nodes
	local numNodes = #nodes
	if numNodes < 4 then
		-- Trivial solution for an input size of 3 or less nodes
		for i = 1, numNodes do
			path[i] = nodes[i]
		end
		-- Create a copy of the metadata[] table too, if there is one
		local metadata2
		if metadata then
			metadata2 = {}
			for i = 1, numNodes do
				metadata2[i] = {}
				for j = 1, #metadata[i] do
					metadata2[i][j] = metadata[i][j]
				end
			end
		end
		return path, metadata2, TSP:PathLength(path, zoneID), 0, 0
	end

	-- Create a copy of the nodes[] table and use this instead of the original because data could get changed
	local nodes2 = {}
	for i = 1, numNodes do
		nodes2[i] = nodes[i]
	end
	local nodes = nodes2
	-- Create a copy of the metadata[] table too, if there is one
	local metadata2
	if metadata then
		metadata2 = {}
		for i = 1, numNodes do
			metadata2[i] = {}
			for j = 1, #metadata[i] do
				metadata2[i][j] = metadata[i][j]
			end
		end
	end
	local metadata = metadata2
	
	-- Setup ACO parameters
	local startTime
	if nonblocking then
		startTime = GetTime()
	else
		-- See the note in SolveTSPILS: make sure the profiler is running so
		-- the elapsed time below is meaningful on every client.
		if debugprofilestart then debugprofilestart() end
		startTime = debugprofilestop()
	end
	local zoneW, zoneH	= Routes.Dragons:GetZoneSize(zoneID)
	-- Foreground ACO is a single blocking call; keep it inside the UI
	-- watchdog's "script ran too long" window. Background is unbounded.
	local acoTimeBudget = nonblocking and inf or 0.8
	local function acoElapsed()
		if nonblocking then
			return GetTime() - startTime
		end
		return (debugprofilestop() - startTime) / 1000
	end

	local INITIAL_PHEROMONE = parameters.initial_pheromone or 0.1   -- Parameter: Initial pheromone trail value
	local ALPHA             = parameters.alpha or 1                 -- Parameter: Likelihood of ants to follow pheromone trails (larger value == more likely)
	local BETA              = parameters.beta or 6                  -- Parameter: Likelihood of ants to choose closer nodes (larger value == more likely)
	local LOCALDECAY        = parameters.local_decay or 0.2         -- Parameter: Governs local trail decay rate [0, 1]
	local LOCALUPDATE       = parameters.local_update or 0.4        -- Parameter: Amount of pheromone to reinforce local trail update by
	local GLOBALDECAY       = parameters.global_decay or 0.2        -- Parameter: Governs global trail decay rate [0, 1]
	local TWOOPTPASSES      = parameters.twoopt_passes or 3         -- Parameter: Number of times to perform 2-opt passes
	local TWOPOINTFIVEOPT   = parameters.two_point_five_opt or false-- Parameter: Run improved 2-opt pass?
	local QUALITY           = 2 * zoneH                             -- Parameter: Tunable parameter that should be somewhat close to 1/4 to 1/2 (distance) of a good solution
	local numAnts           = ceil(2 * numNodes ^ 0.5)              -- Parameter: Number of ants.
	local LOCALDECAYUPDATE  = LOCALDECAY * LOCALUPDATE              -- Just a constant.
	-- If ALPHA = 0, the closest cities are more likely to be selected.
	-- If BETA = 0, only pheromone amplifications is at work.
	-- The number of ants will directly determine the speed of the algorithm proportionally. More ants will get more optimal results, but don't use more ants than the number of nodes.
	-- You need more ants when there are more nodes to have more chances to find a good path quickly. The usual default is numAnts = numNodes, but this takes too long in WoW.
	local PRUNEDIST         = zoneW * 0.30                          -- Another constant for our own pruning

	local shortestPathLength = math.huge
	local shortestPath = {}

	-- Step 1	- Initialize and generate the weight matrix, the pheromone matrix and the ants
	local weight = {}
	local phero = {}
	local ants = {}
	local prune = {}
	local antprob = {}
	for i = 1, numNodes do
		prune[i] = {}
	end

	for i = 1, numNodes do
		local x1, y1 = floor(nodes[i] / 10000) / 10000, (nodes[i] % 10000) / 10000
		local u = i*numNodes-i
		weight[u] = 0
		phero[u] = INITIAL_PHEROMONE
		for j = i+1, numNodes do
			local x2, y2 = floor(nodes[j] / 10000) / 10000, (nodes[j] % 10000) / 10000
			local u, v = i*numNodes-j, j*numNodes-i
			weight[u] = (((x2 - x1)*zoneW)^2 + ((y2 - y1)*zoneH)^2)^0.5 -- Calc distance between each node pair
			weight[v] = weight[u]
			phero[u] = INITIAL_PHEROMONE -- All pheromone trails start
			phero[v] = INITIAL_PHEROMONE -- with a initial small value
			-- Table containing data for 2-opt pruning operations. This is just a list of nodes that are near each node.
			if weight[u] < PRUNEDIST then
				tinsert(prune[i], j)
				tinsert(prune[j], i)
			end
			-- For taboo regions
			local flag = false
			for m = 1, #taboos do -- loop over every taboo
				local taboo_data = taboos[m] and taboos[m].route
				-- A region with fewer than 3 points is not a polygon (yet), so it
				-- cannot enclose anything; skip it instead of indexing a nil point.
				if taboo_data and #taboo_data >= 3 then
					local last_point = taboo_data[ #taboo_data ]
					local sx, sy = floor(last_point / 10000) / 10000, (last_point % 10000) / 10000
					for n = 1, #taboo_data do
						local point = taboo_data[n]
						local ex, ey = floor(point / 10000) / 10000, (point % 10000) / 10000
						-- inlined the intersection check so that it is faster
						local dx = x2-x1
						local dy = y2-y1
						local numer = dx*(sy-y1) - dy*(sx-x1)
						local demon = dx*(sy-ey) + dy*(ex-sx)
						if demon ~= 0 and dx ~= 0 then
							local u = numer / demon
							local t = (sx + (ex-sx)*u - x1)/dx
							if u >= 0 and u <= 1 and t >= 0 and t <= 1 then
								flag = true
								break
							end
						end
						sx, sy = ex, ey
						last_point = point
					end
					if flag then break end
				end
			end
			if flag then -- we increase/bias the weight by a constant factor and by the zone width, since it passes thru a taboo region
				weight[u] = weight[u] * 2 + zoneW
				weight[v] = weight[u]
			end

			-- Initialize the probability table of travelling from city i to j
			antprob[u] = phero[u] ^ ALPHA / weight[u] ^ BETA
			antprob[v] = antprob[u]
		end
	end
	for k = 1, numAnts do
		ants[k] = {}
		local antpath = ants[k] -- This table will stores both the partially constructed path (from 1 to j) and the remainder unvisited nodes (from j+1 to N)
		for j = 1, numNodes do
			antpath[j] = j
		end
	end

	-- Step 2	- Loop until path has small to no changes over the last MAXUNCHANGEDINTERATION iterations
	local nochanges = 0
	local count = 0
	local MAXUNCHANGEDINTERATION = 3
	if numAnts >= 25 then
		MAXUNCHANGEDINTERATION = 2
	end
	local firstPass = true
	while nochanges < MAXUNCHANGEDINTERATION do
		-- Always let one full pass complete (it populates shortestPath),
		-- then stop when the foreground budget is exhausted.
		if not firstPass and acoElapsed() >= acoTimeBudget then break end
		firstPass = false
		nochanges = nochanges + 1
		count = count + 1
		
		-- Step 3	- Each ant k starts at a randomly selected node
		for k = 1, numAnts do
			local antpath = ants[k]
			local p = random(numNodes)
			antpath[1], antpath[p] = antpath[p], antpath[1]
		end

		-- Step 4	- Construct/path the next N-1 nodes...
		for j = 1, numNodes-1 do
			-- Step 5	- ...for each ant k
			for k = 1, numAnts do
				-- Step 6	- Calculate the probability of visiting each remainder node, and the total probability
				local antpath = ants[k]
				local curnode = antpath[j] -- j is the "current node" index in the path
				local totalprob = 0
				for i = j+1, numNodes do
					local u = curnode*numNodes-antpath[i]
					totalprob = totalprob + antprob[u]
				end
				-- Step 7	- Now randomly choose one of these nodes to go to based on the calculated probabilities
				local p = totalprob * random()
				totalprob = 0
				for i = j+1, numNodes do
					local u = curnode*numNodes-antpath[i]
					totalprob = totalprob + antprob[u]
					if p <= totalprob then
						antpath[j+1], antpath[i] = antpath[i], antpath[j+1]
						phero[u] = (1 - LOCALDECAY) * phero[u] + LOCALDECAYUPDATE -- Perform local pheromone update
						antprob[u] = phero[u] ^ ALPHA / weight[u] ^ BETA -- Update the probability
						break
					end
				end
			end
			if nonblocking then
				yield()
			end
		end

		for k = 1, numAnts do
			-- Send out status update if requested  (this loop is the one that actually takes lots of time)
			if nonblocking and TSPUpdateFrame.statusFunc then
				TSPUpdateFrame.statusFunc(count, (k-1)/numAnts)
			end
			-- Step 8	-- Perform local pheromone update on the path from the last node to the first node for each ant k
			local antpath = ants[k]
			local curnode = antpath[numNodes]
			local nextnode = antpath[1]
			local u = curnode*numNodes-nextnode
			phero[u] = (1 - LOCALDECAY) * phero[u] + LOCALDECAYUPDATE
			antprob[u] = phero[u] ^ ALPHA / weight[u] ^ BETA

			-- Step 9	-- Perform 2-opt on the path to improve it
			--[[for i = 1, TWOOPTPASSES do
				if nonblocking then
					yield()
				end
				if TSP:TwoOpt(antpath, weight, prune) == 0 then
					break
				end
			end]]
			while TSP:TwoOpt(antpath, weight, prune, TWOPOINTFIVEOPT, nonblocking) > 0 do
				-- Cycle the last 3 nodes so that the 2-opt algorithm will work on the last
				-- 3 nodes in the path that got missed (the loop goes from 1 to N-3)
				tinsert(antpath, tremove(antpath, 1))
				tinsert(antpath, tremove(antpath, 1))
				tinsert(antpath, tremove(antpath, 1))
				if nonblocking then
					yield()
				end
			end

			-- Step 10	-- At the same time, we also calculate the length of each ant's tour
			local pathLength = 0
			curnode = antpath[numNodes]
			for i = 1, numNodes do
				nextnode = antpath[i]
				pathLength = pathLength + weight[curnode*numNodes-nextnode]
				curnode = nextnode
			end

			-- Step 11	-- If this ant's path is shorter than the global shortest known solution, copy it
			if pathLength < shortestPathLength then
				shortestPathLength = pathLength
				for i = 1, numNodes do
					shortestPath[i] = antpath[i]
				end
				nochanges = 0 -- There were changes, so reset nochanges counter to 0
			end
		
		end
			
		-- Step 12	- Perform global pheromone trail update on the best known solution
		local curnode = shortestPath[numNodes]
		local tempConstant = GLOBALDECAY * QUALITY / shortestPathLength
		for i = 1, numNodes do
			local nextnode = shortestPath[i]
			local u = curnode*numNodes-nextnode
			phero[u] = (1 - GLOBALDECAY) * phero[u] + tempConstant
			antprob[u] = phero[u] ^ ALPHA / weight[u] ^ BETA -- Update the probability
			curnode = nextnode
		end
		
		-- report how long path this round found (with progress==1)
		if nonblocking and TSPUpdateFrame.statusFunc then
			TSPUpdateFrame.statusFunc(count, 1, shortestPathLength)
			yield()
		end
	end

	do
		-- Perform a non-pruned 2-opt on the final path so that there is absolutely no criss-cross
		local noprune = {}
		for i = 1, numNodes do
			noprune[i] = {}
		end
		for i = 1, numNodes do
			for j = i+1, numNodes do
				tinsert(noprune[i], j)
				tinsert(noprune[j], i)
			end
		end
		while TSP:TwoOpt(shortestPath, weight, noprune, TWOPOINTFIVEOPT, nonblocking) > 0 do
			tinsert(shortestPath, tremove(shortestPath, 1))
			tinsert(shortestPath, tremove(shortestPath, 1))
			tinsert(shortestPath, tremove(shortestPath, 1))
			if nonblocking then
				yield()
			end
		end
		
		-- Recompute the path length
		shortestPathLength = 0
		local curnode = shortestPath[numNodes]
		for i = 1, numNodes do
			local nextnode = shortestPath[i]
			shortestPathLength = shortestPathLength + weight[curnode*numNodes-nextnode]
			curnode = nextnode
		end
	end

	-- Step 13	-- Check the length of the original tour that was sent in in nodes[]
	local pathLength = 0
	for i = 2, numNodes do
		pathLength = pathLength + weight[(i-1)*numNodes-i]
	end
	pathLength = pathLength + weight[numNodes*numNodes-1]

	-- Step 14	-- Check solution with original that was sent in
	if pathLength < shortestPathLength then
		-- TSP didn't find a shorter solution, so copy the input to the output
		for i = 1, numNodes do
			path[i] = nodes[i]
		end
		shortestPathLength = pathLength
	else
		-- TSP found a shorter path than the original, convert our shortest path to the output format wanted
		local meta
		if metadata then
			meta = {}
		end
		for i = 1, numNodes do
			path[i] = nodes[shortestPath[i]]
			if metadata then
				meta[i] = metadata[shortestPath[i]]
			end
		end
		metadata = meta -- prev metadata[] not recycled here, will go out of scope at function end and get GCed
	end

	lastpath = nil

	-- This step is necessary because our pathlength above is calculated from biased data from taboos
	shortestPathLength = TSP:PathLength(path, zoneID)

	if nonblocking then
		startTime = GetTime() - startTime
	else
		startTime = debugprofilestop() - startTime
		startTime = startTime / 1000
	end
	return path, metadata, shortestPathLength, count, startTime
end


-----------------------------------------------------
-- Iterated Local Search solver
--[[
Where the ACO solver above spends most of its time *constructing* tours that it
then throws away, this one constructs a single greedy tour and spends its time
improving it. Three things make that cheap enough to run in a coroutine:

1. Candidate lists. Every node keeps only its k nearest neighbours, sorted by
   edge weight. A 2-opt move that shortens the tour must replace edge (a,b) with
   a strictly shorter edge (a,c), so once the candidate list reaches an edge as
   long as (a,b) no improving move can follow and the scan stops. This is what
   removes the NxN weight matrix -- and with it the 724 node ceiling that matrix
   forced on the ACO path.

2. Don't-look bits. After a move only the handful of nodes whose incident edges
   actually changed are worth re-examining, so the search keeps a queue of dirty
   nodes rather than re-scanning all N every pass.

3. Or-opt. 2-opt alone cannot relocate a short run of nodes to a better part of
   the tour without reversing everything in between. Or-opt moves segments of
   1-3 nodes (in either orientation), which is the cheap move the ACO solver's
   "2.5-opt" only half implements (it relocates single nodes only).

Once local search converges, a double-bridge kick reconnects four tour segments
in a way that neither 2-opt nor Or-opt can undo, and local search runs again
from the eight endpoints it disturbed. Improvements are kept, everything else is
rolled back. That loop consumes whatever time budget it is given, which is the
main behavioural difference from ACO: it stops when you tell it to, not after an
arbitrary number of unchanged passes.

-- An Effective Implementation of the Lin-Kernighan Traveling Salesman Heuristic
-- Keld Helsgaun, 2000. (candidate lists, don't-look bits)
-- Large-Step Markov Chains for the Traveling Salesman Problem
-- Martin, Otto & Felten, 1991. (double-bridge)
]]

local ILS_NEIGHBOURS = 10   -- candidate list size (k)
local ILS_EPSILON    = 1e-9 -- gains below this are floating point noise, not improvements
local ILS_MAXSEGMENT = 3    -- longest segment Or-opt will relocate
-- Measured: depth 4-6 with breadth 2-3 all land within noise of each other,
-- while depth 12 / breadth 5 is consistently worse -- the extra levels cost more
-- budget than the exchanges they find are worth.
local ILS_LK_DEPTH   = 6    -- how far a Lin-Kernighan chain may descend
local ILS_LK_BREADTH = 3    -- how many first level candidates a chain may restart from
local ILS_SA_KICKS   = 20   -- kicks spent measuring uphill deltas before annealing starts
local ILS_SA_ACCEPT  = 0.30 -- share of typical uphill kicks accepted at the starting temperature
local ILS_SA_END     = 0.001-- final temperature as a fraction of the initial one

-- Do segments (ax,ay)-(bx,by) and (cx,cy)-(dx,dy) cross?
-- The ACO path inlines a variant of this that divides by dx and so silently
-- misses vertical segments; this uses the cross-product straddle test instead.
local function segmentsCross(ax, ay, bx, by, cx, cy, dx, dy)
	local rx, ry = bx - ax, by - ay
	local sx, sy = dx - cx, dy - cy
	local denom = rx * sy - ry * sx
	if denom == 0 then return false end -- parallel or collinear
	local qx, qy = cx - ax, cy - ay
	local t = (qx * sy - qy * sx) / denom
	if t < 0 or t > 1 then return false end
	local u = (qx * ry - qy * rx) / denom
	return u >= 0 and u <= 1
end

-- Converts taboo regions to yard space and precomputes a bounding box for each,
-- so most edges can be rejected against a whole polygon with four comparisons.
local function prepareTaboos(taboos, zoneW, zoneH)
	local prepared = {}
	for m = 1, #taboos do
		local route = taboos[m] and taboos[m].route
		local count = route and #route or 0
		if count >= 3 then
			local px, py = {}, {}
			local minx, miny, maxx, maxy = inf, inf, -inf, -inf
			for i = 1, count do
				local id = route[i]
				local x = floor(id / 10000) / 10000 * zoneW
				local y = (id % 10000) / 10000 * zoneH
				px[i], py[i] = x, y
				if x < minx then minx = x end
				if x > maxx then maxx = x end
				if y < miny then miny = y end
				if y > maxy then maxy = y end
			end
			prepared[#prepared+1] = {
				x = px, y = py, n = count,
				minx = minx, miny = miny, maxx = maxx, maxy = maxy,
			}
		end
	end
	return prepared
end

local function crossesAnyTaboo(regions, ax, ay, bx, by)
	local minx, maxx = ax, bx
	if minx > maxx then minx, maxx = maxx, minx end
	local miny, maxy = ay, by
	if miny > maxy then miny, maxy = maxy, miny end
	for m = 1, #regions do
		local region = regions[m]
		if not (maxx < region.minx or minx > region.maxx or maxy < region.miny or miny > region.maxy) then
			local px, py, count = region.x, region.y, region.n
			local sx, sy = px[count], py[count]
			for i = 1, count do
				local ex, ey = px[i], py[i]
				if segmentsCross(ax, ay, bx, by, sx, sy, ex, ey) then
					return true
				end
				sx, sy = ex, ey
			end
		end
	end
	return false
end

-- TSP:SolveTSPILS(nodes, metadata, taboos, zoneID, parameters, path, nonblocking)
-- Arguments and return values are identical to TSP:SolveTSPACO(). The parameters
-- table is read for:
--   algorithm     - handled by the TSP:SolveTSP() dispatcher, ignored here
--   ils_effort    - 1..10, scales the time budget and the no-improvement cutoff
--   ils_neighbours- candidate list size, defaults to 10
-- All other keys (the ACO pheromone settings) are ignored, so the same saved
-- parameters table can feed either solver.
function TSP:SolveTSPILS(nodes, metadata, taboos, zoneID, parameters, path, nonblocking)
	assert(type(nodes) == "table", "SolveTSPILS() expected table in 1st argument, got "..type(nodes).." instead.")
	assert(type(taboos) == "table", "SolveTSPILS() expected table in 3rd argument, got "..type(taboos).." instead.")
	assert(type(parameters) == "table", "SolveTSPILS() expected table in 5th argument, got "..type(parameters).." instead.")

	if type(path) == "table" then
		wipe(path)
	else
		path = {}
	end

	if nonblocking then
		-- Ensure that at least 1 yield() is called in a nonblocking call
		coroutine.yield()
	end

	local numNodes = #nodes

	-- Trivial problem: any ordering of 3 or fewer nodes is optimal
	if numNodes < 4 then
		for i = 1, numNodes do
			path[i] = nodes[i]
		end
		local metadata2
		if metadata then
			metadata2 = {}
			for i = 1, numNodes do
				metadata2[i] = {}
				for j = 1, #metadata[i] do
					metadata2[i][j] = metadata[i][j]
				end
			end
		end
		return path, metadata2, TSP:PathLength(path, zoneID), 0, 0
	end

	local startTime
	if nonblocking then
		startTime = GetTime()
	else
		-- The foreground budget below relies on debugprofilestop(); on some
		-- clients it only measures against an explicit start, so make sure
		-- one is running. Without it elapsedTime() stays ~0 and the run
		-- would be unbounded until the UI watchdog kills it with
		-- "script ran too long".
		if debugprofilestart then debugprofilestart() end
		startTime = debugprofilestop()
	end

	local zoneW, zoneH = Routes.Dragons:GetZoneSize(zoneID)

	-- Unpack the coord IDs once into yard space, so every distance below is a
	-- plain euclidean one with no per-edge scaling
	local X, Y = {}, {}
	for i = 1, numNodes do
		local id = nodes[i]
		X[i] = floor(id / 10000) / 10000 * zoneW
		Y[i] = (id % 10000) / 10000 * zoneH
	end

	------------------------------------------------------------------
	-- Edge weights

	local regions = prepareTaboos(taboos, zoneW, zoneH)
	local tabooCache = #regions > 0 and {} or nil

	-- Same bias the ACO solver applies: an edge crossing a taboo region is not
	-- forbidden, just made expensive enough that the search routes around it
	-- unless there is no alternative. Crossings are memoised because the polygon
	-- test is far more expensive than the distance it decorates.
	local function weight(i, j)
		local dx, dy = X[i] - X[j], Y[i] - Y[j]
		local d = (dx*dx + dy*dy)^0.5
		if not tabooCache then return d end
		local key = i < j and i * numNodes + j or j * numNodes + i
		local crossed = tabooCache[key]
		if crossed == nil then
			crossed = crossesAnyTaboo(regions, X[i], Y[i], X[j], Y[j])
			tabooCache[key] = crossed
		end
		if crossed then return d * 2 + zoneW end
		return d
	end

	------------------------------------------------------------------
	-- Uniform grid, sized for roughly two nodes per cell

	local gridDim = floor((numNodes / 2)^0.5)
	if gridDim < 1 then gridDim = 1 end
	local cellW = zoneW / gridDim
	local cellH = zoneH / gridDim
	if cellW <= 0 then cellW = 1 end
	if cellH <= 0 then cellH = 1 end
	local minCell = cellW < cellH and cellW or cellH

	local cells = {}                    -- cell key -> list of node indices
	local cellOf = {}                   -- node -> cell key
	local cellCX, cellCY = {}, {}       -- node -> cell column, row
	for i = 1, numNodes do
		local cx = floor(X[i] / cellW)
		local cy = floor(Y[i] / cellH)
		if cx < 0 then cx = 0 elseif cx >= gridDim then cx = gridDim - 1 end
		if cy < 0 then cy = 0 elseif cy >= gridDim then cy = gridDim - 1 end
		cellCX[i], cellCY[i] = cx, cy
		local key = cy * gridDim + cx
		local bucket = cells[key]
		if not bucket then
			bucket = {}
			cells[key] = bucket
		end
		bucket[#bucket+1] = i
		cellOf[i] = key
	end

	------------------------------------------------------------------
	-- Candidate lists

	local K = parameters.ils_neighbours or ILS_NEIGHBOURS
	if K > numNodes - 1 then K = numNodes - 1 end

	-- Local search engine and acceptance rule. Both are orthogonal: LK replaces
	-- the 2-opt move with a variable depth chain, annealing replaces "keep only
	-- improvements" with a cooling acceptance probability.
	local useLK = parameters.algorithm == "lk"
	local annealing = parameters.annealing and true or false
	local lkMaxDepth = parameters.lk_depth or ILS_LK_DEPTH
	local lkBreadth = parameters.lk_breadth or ILS_LK_BREADTH

	local effort = parameters.ils_effort or 3
	if effort < 1 then effort = 1 elseif effort > 10 then effort = 10 end

	-- Foreground runs block the client outright, so they get a much smaller
	-- budget than a background run that yields back every frame. This bounds the
	-- whole search, local search included -- an LK chain reverses a slice of the
	-- tour per level, so on a large route even reaching a first local optimum can
	-- outlast anything a player would sit through.
	local timeBudget = nonblocking and (effort * 3) or (effort * 0.3)
	local function elapsedTime()
		if nonblocking then
			return GetTime() - startTime
		end
		return (debugprofilestop() - startTime) / 1000
	end
	-- Hard work backstop for foreground runs: a blocking run must stay well
	-- inside the UI watchdog's "script ran too long" window even if the
	-- client's profiler timing is broken and the time budget above never
	-- triggers. Background runs are unbounded (they yield between chunks).
	local maxExamined = nonblocking and inf or math_max(20000, numNodes * 50)
	local maxKicks = nonblocking and inf or math_max(200, numNodes)

	local cand, candW = {}, {}
	do
		local scratch, rawD = {}, {}
		local function byRawDistance(a, b) return rawD[a] < rawD[b] end

		for i = 1, numNodes do
			local bx, by = cellCX[i], cellCY[i]
			local found = 0
			local extraRings = 0
			wipe(scratch)
			wipe(rawD)

			-- Walk outwards a cell ring at a time. Stop one ring after we have
			-- enough candidates, so nodes near a cell boundary still see the
			-- neighbours sitting just over it.
			for r = 0, gridDim do
				for cy = by - r, by + r do
					if cy >= 0 and cy < gridDim then
						local edgeRow = (cy == by - r) or (cy == by + r)
						local cx = bx - r
						while cx <= bx + r do
							if cx >= 0 and cx < gridDim then
								local bucket = cells[cy * gridDim + cx]
								if bucket then
									for m = 1, #bucket do
										local j = bucket[m]
										if j ~= i then
											local dx, dy = X[i] - X[j], Y[i] - Y[j]
											found = found + 1
											scratch[found] = j
											rawD[j] = (dx*dx + dy*dy)^0.5
										end
									end
								end
							end
							if edgeRow or r == 0 then
								cx = cx + 1
							else
								cx = cx + r + r -- middle rows only have the two edge columns
							end
						end
					end
				end
				if found >= K then
					extraRings = extraRings + 1
					if extraRings > 1 then break end
				end
			end

			-- Nearest K by plain distance...
			table.sort(scratch, byRawDistance)
			local limit = found < K and found or K
			local list, listW = {}, {}
			for m = 1, limit do
				local j = scratch[m]
				list[m] = j
				listW[m] = weight(i, j)
			end
			-- ...then reordered by weight, so a taboo-crossing neighbour sinks to
			-- the end where the early break in the move scans will skip it. Only
			-- K entries, so an insertion sort beats setting up a comparator.
			for m = 2, limit do
				local node, w = list[m], listW[m]
				local q = m - 1
				while q >= 1 and listW[q] > w do
					list[q+1], listW[q+1] = list[q], listW[q]
					q = q - 1
				end
				list[q+1], listW[q+1] = node, w
			end
			cand[i], candW[i] = list, listW

			if nonblocking and i % 64 == 0 then yield() end
		end
	end

	------------------------------------------------------------------
	-- Greedy nearest neighbour seed tour

	local tour, pos = {}, {}
	do
		local visited = {}
		local remaining = {}
		for key, bucket in pairs(cells) do
			remaining[key] = #bucket
		end

		local cur = 1
		visited[cur] = true
		remaining[cellOf[cur]] = remaining[cellOf[cur]] - 1
		tour[1], pos[cur] = cur, 1

		for step = 2, numNodes do
			local bx, by = cellCX[cur], cellCY[cur]
			local best, bestD = nil, inf
			for r = 0, gridDim do
				-- Every point in a ring at cell distance r is at least
				-- (r-1)*minCell away, so once that exceeds the best distance
				-- found there is nothing closer left to find.
				if best and (r - 1) * minCell > bestD then break end
				for cy = by - r, by + r do
					if cy >= 0 and cy < gridDim then
						local edgeRow = (cy == by - r) or (cy == by + r)
						local cx = bx - r
						while cx <= bx + r do
							if cx >= 0 and cx < gridDim then
								local key = cy * gridDim + cx
								if (remaining[key] or 0) > 0 then
									local bucket = cells[key]
									for m = 1, #bucket do
										local j = bucket[m]
										if not visited[j] then
											local dx, dy = X[cur] - X[j], Y[cur] - Y[j]
											local d = (dx*dx + dy*dy)^0.5
											if d < bestD then
												bestD, best = d, j
											end
										end
									end
								end
							end
							if edgeRow or r == 0 then
								cx = cx + 1
							else
								cx = cx + r + r
							end
						end
					end
				end
			end
			if not best then
				-- Shouldn't happen, but never leave the tour short
				for j = 1, numNodes do
					if not visited[j] then best = j break end
				end
			end
			visited[best] = true
			remaining[cellOf[best]] = remaining[cellOf[best]] - 1
			tour[step], pos[best] = best, step
			cur = best
			if nonblocking and step % 64 == 0 then yield() end
		end
	end

	------------------------------------------------------------------
	-- Local search

	local function succ(p) return p == numNodes and 1 or p + 1 end
	local function pred(p) return p == 1 and numNodes or p - 1 end

	-- Reverses the tour between positions i and j inclusive. On a cycle
	-- reversing either arc yields the same tour, so take whichever is shorter --
	-- that alone bounds a move at N/2 swaps instead of N.
	local function reverse(i, j)
		local span = j - i
		if span < 0 then span = span + numNodes end
		span = span + 1
		if span + span > numNodes then
			i, j = succ(j), pred(i)
			span = numNodes - span
		end
		for _ = 1, floor(span / 2) do
			local a, b = tour[i], tour[j]
			tour[i], tour[j] = b, a
			pos[b], pos[a] = i, j
			i = succ(i)
			j = pred(j)
		end
	end

	local queue, inQueue = {}, {}
	local qhead, qtail = 1, 0
	local function enqueue(node)
		if not inQueue[node] then
			inQueue[node] = true
			qtail = qtail + 1
			queue[qtail] = node
		end
	end
	local function dequeue()
		if qhead > qtail then
			qhead, qtail = 1, 0
			return nil
		end
		local node = queue[qhead]
		queue[qhead] = nil
		qhead = qhead + 1
		inQueue[node] = false
		return node
	end

	-- 2-opt around node a, looking along both tour directions.
	-- Forward:  edges (a,b) and (c,d) become (a,c) and (b,d), where b and d are
	--           the successors of a and c. Reversing b..c performs the swap.
	-- Backward: the mirror image using predecessors, reversing a..d.
	local function try2opt(a)
		local list, listW = cand[a], candW[a]
		for dir = 1, 2 do
			local pa = pos[a]
			local b = (dir == 1) and tour[succ(pa)] or tour[pred(pa)]
			local wab = weight(a, b)
			for m = 1, #list do
				local wac = listW[m]
				if wac >= wab then break end -- sorted: nothing shorter follows
				local c = list[m]
				if c ~= b then
					local pc = pos[c]
					local d = (dir == 1) and tour[succ(pc)] or tour[pred(pc)]
					if d ~= a then
						if wab + weight(c, d) - wac - weight(b, d) > ILS_EPSILON then
							if dir == 1 then
								reverse(succ(pa), pc)
							else
								reverse(pa, pred(pc))
							end
							enqueue(a) enqueue(b) enqueue(c) enqueue(d)
							return true
						end
					end
				end
			end
		end
		return false
	end

	-- Lin-Kernighan: a variable depth edge exchange.
	--
	-- Fix t1 and let t2 be its neighbour along the direction being tried. Break
	-- (t1,t2), add a candidate edge (t2,t3), and break the edge (t4,t3) that
	-- adding it forces -- where t4 is whichever neighbour of t3 lies on the arc
	-- running back to t2. Reconnecting t4 to t1 closes the tour again, and that
	-- whole exchange is exactly one 2-opt reversal of the arc t2..t4. So depth 1
	-- is plain 2-opt, and the interesting part is that the new tour has t4 sitting
	-- where t2 was: the same step can be applied again with t2 := t4, chaining
	-- exchanges that no single 2-opt or Or-opt move could reach.
	--
	-- The chain descends while the running gain G (edges removed minus edges
	-- added, excluding the closing edge back to t1) stays positive -- Lin and
	-- Kernighan's observation being that a improving exchange can always be
	-- ordered so every prefix has positive gain. Every level is a real tour, so
	-- the best depth seen is kept simply by unwinding the reversals past it.
	-- Reverses the cyclic run of L positions starting at position s, exactly as
	-- given. reverse() above is free to flip the complementary arc instead, which
	-- describes the same cycle but leaves a different array layout. That is
	-- harmless on its own, but it would desynchronise the virtual stack below
	-- from the array, so LK commits go through this one.
	local function reverseExact(s, L)
		local i = s
		local j = s + L - 1
		if j > numNodes then j = j - numNodes end
		for _ = 1, floor(L / 2) do
			local a, b = tour[i], tour[j]
			tour[i], tour[j] = b, a
			pos[b], pos[a] = i, j
			i = succ(i)
			j = pred(j)
		end
	end

	-- Virtual reversal stack.
	--
	-- A chain has to know what the tour would look like after each exchange in
	-- order to choose the next one. Actually performing the reversal costs O(N),
	-- and a chain that dies has to undo every one it made -- which made the first
	-- cut of this function so expensive that it burned the entire time budget
	-- before local search had converged, and lost to plain 2-opt by 5%.
	--
	-- So the exchanges are only recorded, as intervals, and positions are folded
	-- back through that record on demand. Each recorded reversal is an involution
	-- on positions, so mapping a virtual position to its real array index means
	-- applying them top down, and the reverse means applying them bottom up. That
	-- is O(depth) arithmetic per lookup, and the O(N) work is paid only by the
	-- chain that actually pays off.
	local vrStart, vrLen, vrDepth = {}, {}, 0

	local function vReal(p) -- virtual position -> real array index
		for d = vrDepth, 1, -1 do
			local off = p - vrStart[d]
			if off < 0 then off = off + numNodes end
			if off < vrLen[d] then
				p = vrStart[d] + vrLen[d] - 1 - off
				if p > numNodes then p = p - numNodes end
			end
		end
		return p
	end

	local function vVirtual(p) -- real array index -> virtual position
		for d = 1, vrDepth do
			local off = p - vrStart[d]
			if off < 0 then off = off + numNodes end
			if off < vrLen[d] then
				p = vrStart[d] + vrLen[d] - 1 - off
				if p > numNodes then p = p - numNodes end
			end
		end
		return p
	end

	local lkT2, lkT3, lkT4 = {}, {}, {}    -- nodes touched at each level
	local function tryLK(t1)
		for dir = 1, 2 do
			local forward = (dir == 1)
			for start = 1, lkBreadth do
				vrDepth = 0
				local p1 = vVirtual(pos[t1])
				local t2 = tour[vReal(forward and succ(p1) or pred(p1))]
				local G = weight(t1, t2)
				local depth, bestG, bestDepth = 0, 0, 0
				local exhausted = false

				while depth < lkMaxDepth do
					local list, listW = cand[t2], candW[t2]
					local skip = (depth == 0) and (start - 1) or 0
					local moved = false
					for m = 1, #list do
						-- Sorted candidates: once the added edge costs more than
						-- the gain in hand, no deeper candidate can restore it
						if G - listW[m] <= ILS_EPSILON then break end
						local t3 = list[m]
						if t3 ~= t1 and t3 ~= t2 then
							local p3 = vVirtual(pos[t3])
							local t4 = tour[vReal(forward and pred(p3) or succ(p3))]
							if t4 ~= t1 and t4 ~= t2 then
								if skip > 0 then
									-- Breadth: restart the chain from a different
									-- first level candidate on each pass
									skip = skip - 1
								else
									-- Record the reversal of the arc running from
									-- t2 forward to t4 (or t4 to t2 going back)
									local pa = vVirtual(pos[t2])
									local pb = vVirtual(pos[t4])
									local s = forward and pa or pb
									local e = forward and pb or pa
									local L = e - s
									if L < 0 then L = L + numNodes end
									depth = depth + 1
									vrDepth = depth
									vrStart[depth], vrLen[depth] = s, L + 1
									lkT2[depth], lkT3[depth], lkT4[depth] = t2, t3, t4
									G = G - listW[m] + weight(t4, t3)
									local closeGain = G - weight(t4, t1)
									if closeGain > bestG + ILS_EPSILON then
										bestG, bestDepth = closeGain, depth
									end
									t2 = t4
									moved = true
									break
								end
							end
						end
					end
					if not moved then
						-- No candidate left at this level. If that happened on the
						-- very first one there are no further chains to start.
						exhausted = (depth == 0)
						break
					end
				end

				if bestG > ILS_EPSILON then
					-- Replaying the recorded intervals in order reproduces the
					-- layout the chain was reasoning about, so each one is still
					-- valid in real coordinates as the previous ones land.
					vrDepth = 0
					for d = 1, bestDepth do
						reverseExact(vrStart[d], vrLen[d])
					end
					enqueue(t1)
					for d = 1, bestDepth do
						enqueue(lkT2[d]) enqueue(lkT3[d]) enqueue(lkT4[d])
					end
					return true
				end
				vrDepth = 0
				if exhausted then break end
			end
		end
		return false
	end

	-- Lifts the tour slice [i1..i2] out and reinserts it directly after position
	-- q, optionally back to front. Both ends are non-wrapping, so this is a plain
	-- array shift plus a position repair over the span it moved across.
	local segBuf = {}
	local function moveSegment(i1, i2, q, reversed)
		local segLen = i2 - i1 + 1
		for k = 1, segLen do segBuf[k] = tour[i1 + k - 1] end
		if reversed then
			for k = 1, floor(segLen / 2) do
				segBuf[k], segBuf[segLen - k + 1] = segBuf[segLen - k + 1], segBuf[k]
			end
		end
		if q > i2 then
			local w = i1
			for r = i2 + 1, q do
				local node = tour[r]
				tour[w] = node
				pos[node] = w
				w = w + 1
			end
			for k = 1, segLen do
				local node = segBuf[k]
				tour[w] = node
				pos[node] = w
				w = w + 1
			end
		else
			local w = i2
			for r = i1 - 1, q + 1, -1 do
				local node = tour[r]
				tour[w] = node
				pos[node] = w
				w = w - 1
			end
			for k = segLen, 1, -1 do
				local node = segBuf[k]
				tour[w] = node
				pos[node] = w
				w = w - 1
			end
		end
	end

	-- Or-opt: relocate the 1..3 nodes starting at a, in either orientation, next
	-- to one of the near neighbours of whichever end leads. Segments that wrap
	-- the array end are skipped -- there are at most three of them and the kicks
	-- keep shuffling which nodes land there.
	local function tryOrOpt(a)
		local i1 = pos[a]
		for segLen = 1, ILS_MAXSEGMENT do
			local i2 = i1 + segLen - 1
			if i2 >= numNodes or numNodes - segLen < 3 then break end
			local e = tour[i2]
			local p = tour[pred(i1)]
			local s = tour[i2 + 1]
			local removeGain = weight(p, a) + weight(e, s) - weight(p, s)
			-- Nothing to gain by lifting this exact segment out. A longer one
			-- starting here still might, so widen rather than give up.
			if removeGain > ILS_EPSILON then
				for endSel = 1, 2 do
					local anchor = (endSel == 1) and a or e
					local list, listW = cand[anchor], candW[anchor]
					for m = 1, #list do
						-- Reinsertion costs at least the edge to the anchor, so a
						-- candidate that already exceeds the gain rarely pays for
						-- itself. Not a strict bound once taboo bias makes the
						-- weights non-metric, but it is what keeps the scan short.
						if listW[m] >= removeGain then break end
						local c = list[m]
						local q = pos[c]
						if q < numNodes and (q > i2 or q < i1 - 1) then
							local f = tour[q + 1]
							local wcf = weight(c, f)
							local addF = weight(c, a) + weight(e, f) - wcf
							local addR = weight(c, e) + weight(a, f) - wcf
							local reversed = addR < addF
							local add = reversed and addR or addF
							if removeGain - add > ILS_EPSILON then
								moveSegment(i1, i2, q, reversed)
								enqueue(a) enqueue(e) enqueue(p) enqueue(s) enqueue(c) enqueue(f)
								return true
							end
						end
					end
				end
			end
		end
		return false
	end

	local examined = 0
	local function localSearch()
		while true do
			local a = dequeue()
			if not a then break end
			-- Order matters more than it looks. tryLK commits a reversal at every
			-- level and has to unwind them all when a chain dies, so a failed
			-- chain costs tens of reversals where a failed try2opt costs none.
			-- Running plain 2-opt first means LK is only ever asked about nodes
			-- 2-opt has already given up on, which is exactly where its extra
			-- depth is worth paying for. Or-opt stays last either way: relocating
			-- a short segment is not an exchange LK can express.
			local improved = try2opt(a)
			if not improved and useLK then improved = tryLK(a) end
			if not improved then improved = tryOrOpt(a) end
			if improved then
				enqueue(a)
			end
			examined = examined + 1
			if examined % 32 == 0 then
				if nonblocking then yield() end
				if examined >= maxExamined or elapsedTime() >= timeBudget then
					-- Out of time (or hit the hard work cap). Every move left
					-- the tour valid, so stopping mid-pass just means a less
					-- polished one, not a broken one.
					while dequeue() do end
					break
				end
			end
		end
	end

	local function tourLength()
		local total = 0
		local prev = tour[numNodes]
		for i = 1, numNodes do
			local cur = tour[i]
			total = total + weight(prev, cur)
			prev = cur
		end
		return total
	end

	for i = 1, numNodes do
		enqueue(tour[i])
	end
	localSearch()

	------------------------------------------------------------------
	-- Iterated local search

	-- best[] is the best tour ever seen, current[] the one the search is walking
	-- from. Greedy acceptance keeps them identical; annealing lets current[]
	-- wander uphill, which is the whole point, so best[] has to be kept apart.
	local best, bestLength = {}, tourLength()
	local current, currentLength = {}, bestLength
	for i = 1, numNodes do
		best[i] = tour[i]
		current[i] = tour[i]
	end

	-- Simulated annealing acceptance. A kick that lengthens the tour by delta is
	-- taken with probability exp(-delta/T), so early on the search roams and by
	-- the end it is effectively greedy again. Cooling runs against the elapsed
	-- budget rather than the kick count, so it finishes cooling exactly when time
	-- runs out however fast the kicks happen to be.
	--
	-- The starting temperature is measured rather than guessed. The first few
	-- kicks are judged greedily while their uphill deltas are averaged, and T0 is
	-- then set so a typical uphill kick is accepted about 30% of the time. A
	-- fixed constant cannot do this: the right temperature depends on zone size,
	-- node count and how clustered the nodes are, and being out by an order of
	-- magnitude degenerates into either a random walk or plain greedy acceptance.
	local saTarget = parameters.sa_accept or ILS_SA_ACCEPT
	local saKicks = parameters.sa_kicks or ILS_SA_KICKS
	local tempRatio = parameters.sa_end or ILS_SA_END
	local temp0, saSamples, saSum = nil, 0, 0

	-- The budget is the real stop; this only exists so a 12 node route doesn't
	-- sit there kicking a tour it solved optimally in the first pass. It has to
	-- scale with N, since a big tour keeps finding improvements long after a
	-- small one has run out of them.
	local noImproveLimit = 50 + numNodes * effort
	local kickBuf = {}
	local kicks, sinceImprove = 0, 0

	local quarter = floor(numNodes / 4)
	if quarter >= 1 then
		while sinceImprove < noImproveLimit and kicks < maxKicks do
			local elapsed = elapsedTime()
			if elapsed >= timeBudget then break end

			-- Double bridge: cut the tour into A B C D, reconnect as A C B D
			local p1 = 1 + random(quarter)
			local p2 = p1 + 1 + random(quarter)
			local p3 = p2 + 1 + random(quarter)
			if p3 < numNodes then
				kicks = kicks + 1
				local w = 0
				for i = 1, p1 do w = w + 1 kickBuf[w] = tour[i] end
				for i = p2 + 1, p3 do w = w + 1 kickBuf[w] = tour[i] end
				for i = p1 + 1, p2 do w = w + 1 kickBuf[w] = tour[i] end
				for i = p3 + 1, numNodes do w = w + 1 kickBuf[w] = tour[i] end
				for i = 1, numNodes do
					local node = kickBuf[i]
					tour[i] = node
					pos[node] = i
				end

				-- Only the eight nodes bracketing the four new joins are dirty
				local j2 = p1 + (p3 - p2)
				enqueue(tour[p1]) enqueue(tour[p1 + 1])
				enqueue(tour[j2]) enqueue(tour[j2 + 1])
				enqueue(tour[p3]) enqueue(tour[p3 + 1])
				enqueue(tour[numNodes]) enqueue(tour[1])
				localSearch()

				local length = tourLength()
				local improved = length < bestLength - ILS_EPSILON
				if improved then
					bestLength = length
					for i = 1, numNodes do best[i] = tour[i] end
					sinceImprove = 0
				else
					sinceImprove = sinceImprove + 1
				end

				local accept
				local delta = length - currentLength
				if delta < -ILS_EPSILON then
					accept = true
				elseif not annealing then
					accept = false
				elseif not temp0 then
					-- Still measuring. Behave greedily until there are enough
					-- uphill deltas to set a temperature from.
					saSum = saSum + delta
					saSamples = saSamples + 1
					if saSamples >= saKicks then
						local mean = saSum / saSamples
						temp0 = mean > 0 and (mean / -log(saTarget)) or 0
					end
					accept = false
				else
					local progress = elapsed / timeBudget
					if progress > 1 then progress = 1 end
					local temp = temp0 * tempRatio ^ progress
					accept = temp > 0 and random() < exp(-delta / temp)
				end

				if accept then
					currentLength = length
					for i = 1, numNodes do current[i] = tour[i] end
				else
					for i = 1, numNodes do
						local node = current[i]
						tour[i] = node
						pos[node] = i
					end
				end

				-- Kicks run in the thousands, so only report when there is
				-- something new to say or enough of them have gone by to be worth
				-- moving the progress readout
				if nonblocking and TSPUpdateFrame.statusFunc and (improved or kicks % 256 == 0) then
					local progress = elapsed / timeBudget
					if progress > 1 then progress = 1 end
					TSPUpdateFrame.statusFunc(kicks, progress, bestLength)
					yield()
				end
			else
				break -- too few nodes for a double bridge to have four parts
			end
		end
	end

	------------------------------------------------------------------
	-- Emit the better of our result and the tour that was handed to us

	local inputLength = 0
	do
		local prev = numNodes
		for i = 1, numNodes do
			inputLength = inputLength + weight(prev, i)
			prev = i
		end
	end

	if inputLength <= bestLength then
		for i = 1, numNodes do
			path[i] = nodes[i]
		end
	else
		local meta
		if metadata then meta = {} end
		for i = 1, numNodes do
			local index = best[i]
			path[i] = nodes[index]
			if metadata then meta[i] = metadata[index] end
		end
		metadata = meta
	end

	-- Report the real length, not the taboo-biased one the search optimised
	local pathLength = TSP:PathLength(path, zoneID)

	if nonblocking then
		startTime = GetTime() - startTime
	else
		startTime = (debugprofilestop() - startTime) / 1000
	end
	return path, metadata, pathLength, kicks, startTime
end


-- TSP:TwoOpt(path, weight)
-- Arguments
--   path   - The table containing a TSP path to improve. Input must have node IDs 1-N, numerically indexed.
--   weight - The table containing the NxN weight matrix.
--   prune  - The table containing the list of neighbouring nodes for each node.
--   twoPointFiveOpt - A boolean indicating whether to perform 2.5-opt.
--   nonblocking - A boolean indicating whether the function should yield() regularly.
-- Returns
--   count  - The number of 2-opt replacements made to path[]
--[[
Typically TSP tour refinement takes place by "flipping" edges. For example, if
the tour contains the edges (v1, w1) and (w2, v2) in that order, then these two
edges can always be flipped to create (v1, w2) and (w1, v2). This sort of step
forms the basis of the 2-opt algorithm which is a steepest descent approach,
repeatedly flipping pairs of edges if they improve the tour quality until it
reaches a local minimum of the objective function and no more such flips exist.

In a similar vein, the 3-opt algorithm exchanges 3 edges at a time. These are
more specific versions of the Lin-Kernighan (LK) algorithm or better known as
the N-opt or variable-opt algorithm.

-- A Multilevel Lin-Kernighan-Helsgaun Algorithm for the Travelling Salesman Problem
-- Chris Walshaw, September 27, 2001.
]]
function TSP:TwoOpt(path, weight, prune, twoPointFiveOpt, nonblocking)
	local count = 0
	local numNodes = #path
	local pathR = pathR

	-- Generate reverse lookup table
	if lastpath ~= path then
		for i = 1, numNodes do
			pathR[path[i]] = i
		end
	end

	-- Perform normal 2-opt
	for i = 1, numNodes-3 do
		local a, b = path[i], path[i+1]
		local z = weight[a*numNodes-b]
		--for j = i+2, numNodes-1 do
		for m = 1, #prune[a] do
			local j = pathR[prune[a][m]]
			if j > i+1 and j ~= numNodes then
				local c, d = path[j], path[j+1]
				local currW = z + weight[c*numNodes-d]
				local newW = weight[a*numNodes-c] + weight[b*numNodes-d]
				if newW < currW then
					-- Swap these 2 edges to get a shorter path
					-- This is done by reversing the node order between i+1 to j
					local left = i+1
					local right = j
					while left < right do
						local L, R = path[right], path[left]
						path[left], path[right] = L, R
						pathR[L], pathR[R] = left, right
						left = left + 1
						right = right - 1
					end
					b = path[i+1]
					z = weight[a*numNodes-b]
					count = count + 1
				end
			end
		end
	end

	-- Then perform 2.5-opt
	if twoPointFiveOpt then
		if nonblocking then
			yield()
		end
		for i = 1, numNodes-4 do
			local a, b, c = path[i], path[i+1], path[i+2]
			local z = weight[a*numNodes-b] + weight[b*numNodes-c]
			for m = 1, #prune[a] do
				local j = pathR[prune[a][m]]
				if j > i+2 and j ~= numNodes then
					local d, e = path[j], path[j+1]
					local currW = z + weight[d*numNodes-e]
					local newW = weight[a*numNodes-c] + weight[d*numNodes-b] + weight[b*numNodes-e]
					if newW < currW then
						-- Remove node b from the path, then reinsert it between d and e
						for q = i+1, j-1 do
							path[q] = path[q+1]
							pathR[path[q]] = q
						end
						path[j] = b
						pathR[b] = j
						b, c = path[i+1], path[i+2]
						z = weight[a*numNodes-b] + weight[b*numNodes-c]
						count = count + 1
					end
				end
			end
		end
	end

	lastpath = path
	return count
end

-- Helper function for TSP:InsertNode()
-- Tries to insert node into an existing cluster
-- Returns true if successful, false otherwise
local function tryInsert(nodes, metadata, insertPoint, nodeID, radius, zoneW, zoneH)
	local x, y = floor(nodeID / 10000) / 10000, (nodeID % 10000) / 10000
	local x2, y2 = floor(nodes[insertPoint] / 10000) / 10000, (nodes[insertPoint] % 10000) / 10000
	-- Calculate the new centroid and coord
	local num = #metadata[insertPoint]
	x2, y2 = (x2*num+x)/(num+1), (y2*num+y)/(num+1)
	local coord = floor(x2 * 10000 + 0.5) * 10000 + floor(y2 * 10000 + 0.5)
	x2, y2 = floor(coord / 10000) / 10000, (coord % 10000) / 10000 -- to round off the coordinate
	-- Check that the merged point is valid
	for i = 1, num do
		local coord = metadata[insertPoint][i]
		local x, y = floor(coord / 10000) / 10000, (coord % 10000) / 10000
		local t = (((x2 - x)*zoneW)^2 + ((y2 - y)*zoneH)^2)^0.5
		if t > radius then
			return false
		end
	end
	tinsert(metadata[insertPoint], nodeID)
	nodes[insertPoint] = coord
	return true
end

-- TSP:InsertNode(nodes, zoneID, nodeID, twoOpt, path)
--   Inserts a node into an existing route.
-- Arguments
--   nodes       - The table containing a list of Routes node IDs to path
--                 This list should only contain nodes on the same map. This
--                 table should be indexed numerically from nodes[1] to nodes[n].
--   metadata    - The table containing the cluster metadata, if available
--   zoneID      - The map area ID of the map that the route is on.
--   nodeID      - The Routes node ID to insert into the route.
-- Returns
--   pathLength  - The length of the route in yards.
-- Notes: This function modifies the original nodes[] and metadata[] tables
--        directly
function TSP:InsertNode(nodes, metadata, zoneID, nodeID, radius)
	assert(type(nodes) == "table", "InsertNode() expected table in 1st argument, got "..type(nodes).." instead.")

	-- Check for trivial problem of 2 or less nodes
	local numNodes = #nodes
	if numNodes < 3 then
		-- Trivial solution for an input size of 2 or less nodes
		nodes[numNodes+1] = nodeID
		if metadata then
			metadata[numNodes+1] = {nodeID}
		end
		return TSP:PathLength(nodes, zoneID)
	end

	-- Insert the node to be added at the end of the list.
	tinsert(nodes, nodeID)
	numNodes = #nodes

	-- Step 1	- Initialize and generate the weight matrix, and prune matrix if doing 2-opt
	local zoneW, zoneH = Routes.Dragons:GetZoneSize(zoneID)
	local weight = {}

	-- Not doing a twoopt means we only need to generate O(2n) entries in the weight table
	local x, y, x2, y2
	for i = 1, numNodes-2 do
		-- for every node i, calculate its distance to node i+1
		x, y = floor(nodes[i] / 10000) / 10000, (nodes[i] % 10000) / 10000
		x2, y2 = floor(nodes[i+1] / 10000) / 10000, (nodes[i+1] % 10000) / 10000
		weight[i*numNodes-(i+1)] = (((x2 - x)*zoneW)^2 + ((y2 - y)*zoneH)^2)^0.5 -- Calc distance
	end
	-- do looparound node
	x, y = floor(nodes[numNodes-1] / 10000) / 10000, (nodes[numNodes-1] % 10000) / 10000
	x2, y2 = floor(nodes[1] / 10000) / 10000, (nodes[1] % 10000) / 10000
	weight[(numNodes-1)*numNodes-1] = (((x2 - x)*zoneW)^2 + ((y2 - y)*zoneH)^2)^0.5 -- Calc distance
	-- calc distance for every node to the node to be inserted
	x2, y2 = floor(nodes[numNodes] / 10000) / 10000, (nodes[numNodes] % 10000) / 10000
	for i = 1, numNodes-1 do
		x, y = floor(nodes[i] / 10000) / 10000, (nodes[i] % 10000) / 10000
		local u, v = i*numNodes-numNodes, numNodes*numNodes-i
		weight[u] = (((x2 - x)*zoneW)^2 + ((y2 - y)*zoneH)^2)^0.5 -- Calc distance
		weight[v] = weight[u]
	end

	-- Step 2	- Find the best place to insert the node
	local shortestPathLength = math.huge -- Some large value
	local insertPoint
	for i = 1, numNodes-2 do
		local z = weight[i*numNodes-numNodes] + weight[numNodes*numNodes-(i+1)] - weight[i*numNodes-(i+1)]
		if z < shortestPathLength then
			shortestPathLength = z
			insertPoint = i + 1
		end
	end
	if weight[(numNodes-1)*numNodes-numNodes] + weight[numNodes*numNodes-1] - weight[(numNodes-1)*numNodes-1] < shortestPathLength then
		-- Do nothing, inserting the node at the last place is the best, already inserted here.
		if metadata then
			tremove(nodes)
			local try1, try2 = numNodes-1, 1
			if weight[(numNodes-1)*numNodes-numNodes] > weight[numNodes*numNodes-1] then
				try1, try2 = try2, try1 -- try the closer node first
			end
			local flag = tryInsert(nodes, metadata, try1, nodeID, radius, zoneW, zoneH)
			if not flag then
				flag = tryInsert(nodes, metadata, try2, nodeID, radius, zoneW, zoneH)
			end
			if not flag then -- both clusters failed, so insert a new cluster
				tinsert(nodes, nodeID)
				tinsert(metadata, {nodeID})
			end
		end
	else
		-- Remove it from the last place in the path and insert it at the best place found.
		tremove(nodes)
		if metadata then
			local try1, try2 = insertPoint-1, insertPoint
			if weight[(insertPoint-1)*numNodes-numNodes] > weight[numNodes*numNodes-insertPoint] then
				try1, try2 = try2, try1
			end
			local flag = tryInsert(nodes, metadata, try1, nodeID, radius, zoneW, zoneH)
			if not flag then
				flag = tryInsert(nodes, metadata, try2, nodeID, radius, zoneW, zoneH)
			end
			if not flag then
				tinsert(nodes, insertPoint, nodeID)
				tinsert(metadata, insertPoint, {nodeID})
			end
		else
			tinsert(nodes, insertPoint, nodeID)
		end
	end

	return TSP:PathLength(nodes, zoneID)
end


-- TSP:PathLength(nodes, zoneID)
--   Returns how long a given route is in yards.
-- Arguments
--   nodes      - The table containing a list of Routes node IDs to path
--                This list should only contain nodes on the same map. This
--                table should be indexed numerically from nodes[1] to nodes[n].
--   zoneID     - The map area ID of the map that the route is on.
-- Returns
--   pathLength - The length of the route in yards.
function TSP:PathLength(nodes, zoneID)
	assert(type(nodes) == "table", "PathLength() expected table in 1st argument, got "..type(nodes).." instead.")
	local zoneW, zoneH = Routes.Dragons:GetZoneSize(zoneID)
	local numNodes = #nodes
	local pathLength = 0

	-- Check for trivial problem of 1 or less nodes
	if numNodes <= 1 then
		return 0
	end

	-- Get coordinate of last node
	local x2, y2 = floor(nodes[numNodes] / 10000) / 10000, (nodes[numNodes] % 10000) / 10000
	for i = 1, #nodes do
		local x, y = floor(nodes[i] / 10000) / 10000, (nodes[i] % 10000) / 10000
		pathLength = pathLength + (((x2 - x)*zoneW)^2 + ((y2 - y)*zoneH)^2)^0.5
		x2, y2 = x, y
	end

	return pathLength
end

-- TSP:ClusterRoute(nodes, zoneID, radius)
-- Arguments
--   nodes    - The table containing a list of Routes node IDs to path
--              This list should only contain nodes on the same map. This
--              table should be indexed numerically from nodes[1] to nodes[n].
--   zoneID   - The map area ID the route is in
--   radius   - The radius in yards to cluster
-- Returns
--   path     - The result TSP path is a table indexed numerically from path[1]
--              to path[n], a list of Routes node IDs. n is usually smaller than
--              the original input
--   metadata - The metadata table for path[] containing the original nodes
--              clustered
--   length   - The length of the new route in yards
-- Notes: The original table sent in is unmodified. New tables are returned.
--[[
Fast radius clustering

The route is clustered by grouping nearby points around a centroid while
ensuring every original node in a cluster remains within the configured radius
of that centroid. A spatial grid limits candidate checks to nearby nodes, so
large data-source routes finish quickly enough for WoW clients while preserving
the important guarantee that clustering is reversible through metadata.
]]function TSP:ClusterRoute(nodes, zoneID, radius, nonblocking)
	local numNodes = #nodes
	local zoneW, zoneH = Routes.Dragons:GetZoneSize(zoneID)
	local diameter = radius * 2
	local radius2 = radius * radius
	local diameter2 = diameter * diameter

	-- Background clustering is started from an AceConfig button click. Yield
	-- before doing any real work so the click handler can return immediately on
	-- Classic Era instead of tripping the UI watchdog on large routes.
	if nonblocking then
		coroutine.yield()
	end

	-- The original agglomerative clustering implementation repeatedly scanned
	-- an NxN distance matrix and removed matrix columns with tremove(). That is
	-- close to O(n^3) and can take many minutes for large GatherMate routes even
	-- when chunked across frames. Use a spatial grid instead: each cluster starts
	-- from one unassigned route point and only considers unassigned neighbours
	-- within 2r, because no valid cluster member can be farther than 2r from any
	-- other member when every member must remain within r of the centroid.
	local X, Y, cellX, cellY = {}, {}, {}, {}
	local cells = {}
	local cellSize = radius
	if cellSize <= 0 then cellSize = 1 end
	local cellRange = 2 -- diameter / cellSize

	for i = 1, numNodes do
		local coord = nodes[i]
		local x = floor(coord / 10000) / 10000 * zoneW
		local y = (coord % 10000) / 10000 * zoneH
		X[i], Y[i] = x, y
		local cx, cy = floor(x / cellSize), floor(y / cellSize)
		cellX[i], cellY[i] = cx, cy
		local key = cx .. ":" .. cy
		local bucket = cells[key]
		if not bucket then
			bucket = {}
			cells[key] = bucket
		end
		bucket[#bucket+1] = i
		if nonblocking and i % 256 == 0 then yield() end
	end

	local unassigned = {}
	for i = 1, numNodes do
		unassigned[i] = true
	end

	local clustered, metadata = {}, {}
	local candidateDistance = {}
	local function bySeedDistance(a, b)
		return candidateDistance[a] < candidateDistance[b]
	end

	for seed = 1, numNodes do
		if unassigned[seed] then
			unassigned[seed] = false
			local cluster = { seed }
			local sumX, sumY = X[seed], Y[seed]
			local count = 1

			local candidates = {}
			for k in pairs(candidateDistance) do candidateDistance[k] = nil end
			local n = 0
			local seedCellX, seedCellY = cellX[seed], cellY[seed]
			for gy = seedCellY - cellRange, seedCellY + cellRange do
				for gx = seedCellX - cellRange, seedCellX + cellRange do
					local bucket = cells[gx .. ":" .. gy]
					if bucket then
						for bi = 1, #bucket do
							local j = bucket[bi]
							if unassigned[j] then
								local dx, dy = X[j] - X[seed], Y[j] - Y[seed]
								local d2 = dx*dx + dy*dy
								if d2 <= diameter2 then
									n = n + 1
									candidates[n] = j
									candidateDistance[j] = d2
								end
							end
						end
					end
				end
				if nonblocking then yield() end
			end
			table.sort(candidates, bySeedDistance)

			for ci = 1, #candidates do
				local j = candidates[ci]
				if unassigned[j] then
					local newCount = count + 1
					local centroidX = (sumX + X[j]) / newCount
					local centroidY = (sumY + Y[j]) / newCount
					local ok = true
					for m = 1, #cluster do
						local node = cluster[m]
						local dx, dy = X[node] - centroidX, Y[node] - centroidY
						if dx*dx + dy*dy > radius2 then
							ok = false
							break
						end
					end
					if ok then
						local dx, dy = X[j] - centroidX, Y[j] - centroidY
						if dx*dx + dy*dy > radius2 then
							ok = false
						end
					end
					if ok then
						unassigned[j] = false
						cluster[#cluster+1] = j
						sumX, sumY = sumX + X[j], sumY + Y[j]
						count = newCount
					end
				end
				if nonblocking and ci % 64 == 0 then yield() end
			end

			local outIndex = #clustered + 1
			local centroidX, centroidY = sumX / count, sumY / count
			clustered[outIndex] = floor(centroidX / zoneW * 10000 + 0.5) * 10000 + floor(centroidY / zoneH * 10000 + 0.5)
			metadata[outIndex] = {}
			for m = 1, #cluster do
				metadata[outIndex][m] = nodes[cluster[m]]
			end
		end
		if nonblocking and seed % 64 == 0 then yield() end
	end

	return clustered, metadata, TSP:PathLength(clustered, zoneID)
end

function TSP:ClusterRouteBackground(nodes, zoneID, radius, finishFunc)
	if not TSPClusterFrame.running and not TSPUpdateFrame.running then
		TSPClusterFrame.co = coroutine.create(TSP.ClusterRoute)
		TSPClusterFrame.finishFunc = finishFunc
		TSPClusterFrame:SetScript("OnUpdate", TSPClusterFrame.OnUpdate)
		TSPClusterFrame.running = true
		TSPClusterFrame.nodes = nodes
		local status = coroutine.resume(TSPClusterFrame.co, TSP, nodes, zoneID, radius, true)
		if status then
			-- Do nothing, path isn't complete because at least 1 yield() is called.
			return 1
		else
			-- An error occured in the coroutine, abort and return the error message.
			TSPClusterFrame.running = false
			TSPClusterFrame:SetScript("OnUpdate", nil)
			TSPClusterFrame.co = nil
			TSPClusterFrame.nodes = nil
			return 3
		end
	else
		-- There is already a TSP or clustering job running
		return 2
	end
end

-- TSP:DecrossRoute(nodes)
-- Arguments
--   nodes    - The table containing a list of Routes node IDs to path
--              This list should only contain nodes on the same map. This
--              table should be indexed numerically from nodes[1] to nodes[n].
-- Returns nothing
-- Notes: The original table sent in is modified directly
-- 
-- This function is contributed by Polarina for quickly solving a TSP in
-- O(n log n). The method merely calculates a centroid, and compares the angle
-- of every node with the centroid and sorts it that way, resulting in a tour
-- that doesn't cross itself, but obviously not ideal. Used for initial route
-- creation to get an initial quality value.
function TSP:DecrossRoute(nodes)
	local numNodes = #nodes
	local math_atan2 = math.atan2

	-- Find the nodes centroid
	local x, y = 0, 0
	for index, value in ipairs(nodes) do
		x = x + floor(value / 1e4)
		y = y + value % 1e4
	end
	x = x / numNodes
	y = y / numNodes

	-- From the middle, link all nodes in a circle
	table.sort(nodes, function(a, b)
		local aX = floor(a / 1e4)
		local aY = a % 1e4
		local bX = floor(b / 1e4)
		local bY = b % 1e4
		return math_atan2(aY - y, aX - x) < math_atan2(bY - y, bX - x)
	end)

	--[[
	local weight = {}
	local path = {}
	local prune = {}
	for i = 1, numNodes do
		prune[i] = {}
	end

	for i = 1, numNodes do
		local x1, y1 = floor(nodes[i] / 10000) / 10000, (nodes[i] % 10000) / 10000
		local u = i*numNodes-i
		weight[u] = 0
		for j = i+1, numNodes do
			local x2, y2 = floor(nodes[j] / 10000) / 10000, (nodes[j] % 10000) / 10000
			local u, v = i*numNodes-j, j*numNodes-i
			weight[u] = ((x2 - x1)^2 + (y2 - y1)^2)^0.5 -- Calc distance between each node pair
			weight[v] = weight[u]
			--if weight[u] < 0.4 then
				tinsert(prune[i], j)
				tinsert(prune[j], i)
			--end
		end
		path[i] = i
	end

	while TSP:TwoOpt(path, weight, prune, false, false) > 0 do end

	local newpath = {}
	for i = 1, numNodes do
		newpath[i] = nodes[ path[i] ]
	end

	return newpath]]

	return nodes
end

-- vim: ts=4 noexpandtab
