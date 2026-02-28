
function thIcs = cs_clearskyOnSurface( Time, Location, angle )
   consts;
   [In, Id, s_alt, c_alt, s_az, c_az ] = cs_In( Time, Location )
   thIcs = cs_In2Ib( In, s_alt, c_alt, s_az, c_az, angle ) + ( Id * FLAG_ID );
   
end
