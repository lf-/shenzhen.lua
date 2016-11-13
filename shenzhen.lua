if not serpent then
	serpent = require('serpent')
end

debug_on = true

state_proto = {
	acc = 0,
	dat = 0,
	last_cond = 0
}

line_proto = {
	conditional = 0,  -- none: 0; +: 1, -: 2, checks result of last compare
	instruction = nop,  -- instruction to execute, function type
	params = {nil, nil} -- instruction params
}

regs = {
	acc = true,
	dat = true
}

------------------------------------------------------------------------------
-- Library bits. No comment on stdlib.
------------------------------------------------------------------------------

function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function string:split(sSeparator, nMax, bRegexp)
	assert(sSeparator ~= '')
	assert(nMax == nil or nMax >= 1)

	local aRecord = {}

	if self:len() > 0 then
		local bPlain = not bRegexp
		nMax = nMax or -1

		local nField, nStart = 1, 1
		local nFirst,nLast = self:find(sSeparator, nStart, bPlain)
		while nFirst and nMax ~= 0 do
			aRecord[nField] = self:sub(nStart, nFirst-1)
			nField = nField+1
			nStart = nLast+1
			nFirst,nLast = self:find(sSeparator, nStart, bPlain)
			nMax = nMax-1
		end
		aRecord[nField] = self:sub(nStart)
	end

	return aRecord
end

function stringify(thing)
	-- str(string) for lua...
	thing_type = type(thing)
	if (thing_type == 'string' or thing_type == 'number' or
			thing_type == 'boolean') then
		return thing
	elseif thing_type == 'nil' then
		return 'nil'
	else
		return serpent.block(thing)
	end
end

function debug(...)
	local args = {...}
	if debug_on then
		local out = {}
		for k, v in pairs(args) do
			out[k] = stringify(v)
		end
		print(table.concat(out, ' '))
	end
end

function get_reg_int(reg_int)
	if regs[reg_int] then
		return regs[reg_int]
	elseif tonumber(reg_int) ~= nil then
		return tonumber(reg_int)
	else
		return nil
	end
end

function check_reg(reg)
	return (not not regs[reg])
end

------------------------------------------------------------------------------
-- Instructions
------------------------------------------------------------------------------

function nop(state, param1, param2)
	-- nop instruction, does nothing
	-- ensure there are no args
	debug('nop:', param1, param2)
end

function mov(state, param1, param2)
	-- mov reg/int reg/int
	debug('mov:', param1, param2)
	assert(param1 ~= nil and param2 ~= nil, 'mov: need two parameters')
	local param1 = get_reg_int(param1)
	assert(param1 ~= nil, 'mov: param1 must be reg/int')
	assert(check_reg(param2), 'mov: param2 must be reg')
	assert(not tonumber(param2), 'mov: cannot assign to integer')
	state[param2] = tonumber(param1)
end

function jmp(state, param1, param2)
	-- this doesn't do anything, functionality is implemented in interpret()
	assert(param1 and not param2, 'jmp: 1 argument required')
end

function add(state, param1, param2)
	debug('add:', param1, param2)
	assert(param1 ~= nil and not param2, 'add: 1 parameter required')
	local param1 = get_reg_int(param1)
	assert(param1 ~= nil, 'add: param1 must be reg/int')
	state.acc = state.acc + param1
end

function teq(state, param1, param2)
	debug('teq:', param1, param2)
	assert(param1 ~= nil and param2 ~= nil, 'teq: need two parameters')
	param1 = get_reg_int(param1)
	param2 = get_reg_int(param2)
	assert(param1 ~= nil, 'teq: param1 must be reg/int')
	assert(param2 ~= nil, 'teq: param2 must be reg/int')
	compare = param1 == param2
	if compare == true then
		state.last_cond = 1
	else
		state.last_cond = 2
	end
end


function slp(state, param1, param2)
	assert(param1 and not param2, 'slp: 1 argument required')
	local t0 = os.clock()
	while os.clock() - t0 <= tonumber(param1) do end
end

------------------------------------------------------------------------------
-- Infrastructure
------------------------------------------------------------------------------

function dispatch_instruction(state, instr, param1, param2)
	-- Processes an instruction, sending it to the appropriate handler
	instr(state, param1, param2)
	debug('state:', state)
end

function load_shenzhen(code)
	-- "compile" shenzhen io code
	-- Limitations:
	-- * does not support missing spaces around labels
	--     or conditional prefixes
	-- Returns:
	-- tokenized output in list of lines, labels in {label: out_idx}
	local lines = code:split('\n')
	local out = {}
	local labels = {}
	for _, line in pairs(lines) do
		if line == '' then
			-- ignore blank lines
			goto load_continue
		end
		local comps = line:split(' +', nil, true)
		local ln = {}

		-- check for label
		label_match = comps[1]:match('^([^:]+):$')
		if label_match then
			labels[label_match] = #out + 1
			table.remove(comps, 1)
		end

		-- check for conditional prefix
		if comps[1] == '+' then
			ln.conditional = 1
			table.remove(comps, 1)
		elseif comps[1] == '-' then
			ln.conditional = 2
			table.remove(comps, 1)
		else
			ln.conditional = 0
		end
		-- empty string instruction. This may occur if there's a line like
		-- `label:`
		if comps[1] == nil then
			table.insert(comps, 1, '')
		end
		assert(instructions[comps[1]], 'load: no such instruction ' .. comps[1])
		ln.instruction = instructions[comps[1]]
		ln.params = {comps[2], comps[3]}
		table.insert(out, ln)
		-- no good. Lua needs a continue statement!
		::load_continue::
	end
	return out, labels
end

function interpret(code)
	-- takes some lines of code then runs them
	local state = shallowcopy(state_proto)
	local code, labels = load_shenzhen(code)
	state.next = 1
	while true do
		local next_instr = code[state.next]
		if next_instr.conditional == last_cond or next_instr.conditional == 0 then
			dispatch_instruction(state, next_instr.instruction, next_instr.params[1], next_instr.params[2])
		end
		if code[state.next + 1] and code[state.next + 1].instruction == jmp then
			state.next = labels[code[state.next + 1].params[1]]
		else
			if code[state.next + 1] then
				state.next = state.next + 1
			else
				-- wrap around if hit end
				state.next = 1
			end	
		end
	end
end


instructions = {
	nop = nop,
	mov = mov,
	slp = slp,
	add = add,
	jmp = jmp,
	teq = teq,
	[''] = nop  -- this is implemented for labels on lines by themselves
}