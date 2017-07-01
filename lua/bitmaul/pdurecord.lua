-- pdurecord.lua 
-- 	PDU layer attached to a stream 

local SweepBuf=require'sweepbuf'

local dbg=require 'debugger'

local PDURecord = {

	-- States
	--       0: start 
	--       1: want_bytes
	--       2: want_pattern
	--       3: skip_bytes 
	--       4: abort 

	-- TODO: unoptimized 
	-- 
	push_chunk = function( tbl, segment_seek, incomingbuf  )

		local st = tbl.state

		-- fast cases 
		if st==4 then 
			return 	-- abort
		elseif st==3 and segment_seek + #incomingbuf <= tbl._sweepbuffer.abs_seek()  then
			return  -- skip mode , streaming will resume at tbl.seek 
		elseif segment_seek + #incomingbuf > tbl._sweepbuffer.right then
			-- update buffer  
			tbl._sweepbuffer = tbl._sweepbuffer + SweepBuf.new(incomingbuf,segment_seek)
		elseif not tbl._sweepbuffer:has_more() then
			print("EMPTY BUFFER")
			return
		end 

		print("SWEEP + " .. tostring(tbl._sweepbuffer))



		if st==4 then
			-- STATE abort 
			return
		elseif st==3 then 
			-- STATE skipping 
			local ol = tbl.skip_to_pos - segment_seek
			if ol  > 0  then 
				tbl._sweepbuffer = SweepBuf.new(string.sub(incomingbuf,ol),tbl.skip_to_pos)
				tbl.state=0
			else
				return
			end
		elseif st==2 then
			-- STATE want pattern
			local mb = tbl._sweepbuffer:next_str_to_pattern(tbl.want_pattern)
			if mb then 
				tbl.diss:on_record(tbl, mb ) 	--> * emit *
				tbl.state=0
			end
		elseif st==1 then
			-- STATE_want bytes
			if  tbl._sweepbuffer:bytes_left() >= tbl.want_bytes then  
				local nbuff  = tbl._sweepbuffer:next_str_to_len(tbl.want_bytes)
				tbl.diss:on_record(tbl, nbuff ) 	--> * emit *
				tbl.state=0
			end
		elseif st==0 then
			tbl.diss:what_next( tbl, tbl._sweepbuffer)
		end

	end,

	-- state changes
	want_next = function(tbl, bytes )
		tbl.want_bytes=bytes
		tbl.state =1
	end,

	want_to_pattern = function(tbl, patt )
		tbl.want_pattern=patt
		tbl.state =2
	end,

	skip_next = function(tbl, bytes)
		local skip_to_pos = tbl._sweepbuffer.abs_seek() + bytes
		tbl._sweepbuffer = SweepBuf.new("",skip_to_pos)
		tbl.state = 3
	end,

	-- cant restart from here , let GC pick up right away  
	abort = function()
		tbl.state = 4 
		tbl._sweepbuffer = nil 
	end,


}

local pmt = {
	__index = PDURecord ,
	__tostring = function(p) 
			  return string.format( "PDU/%s  State=%d  Pos=%d Next=%d B=%s", 
									p.id, p.state, p.seek, p.next_pdu,  tostring(p._sweepbuffer))
	end

}

local pdurecord = {

		new = function( id , dissector  ) 

			local pstate = { 
				id = id ,
				state =  0,   
				diss = dissector,
			    _sweepbuffer = SweepBuf.new("",0)
			}
				
			return setmetatable( pstate, pmt) 
		end 	
}

return pdurecord;