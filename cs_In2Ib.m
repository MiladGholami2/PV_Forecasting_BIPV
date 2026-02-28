%                       ------------------------------
%                       --- CAST FROM GHI/IN TO IB ---
%                       ------------------------------

function I = cs_In2Ib(In, s_alt, c_alt, s_az, c_az, angle)
% In: normal irradiance [W/m^2]
% s_alt, c_alt, s_az, c_az: sin and cos of sun altitude and azimuth angles [degree]
% angle = [ tilt, azimuth ]: panel tilt and azimuth angles [degree]
   consts;
   p1 = c_alt.*s_az;
   p2 = c_alt.*c_az;
   tilt = angle(1);
   azimuth = angle(2);
   
   I = In.*( p1*sind(tilt)*sind(azimuth) + p2*sind(tilt)*cosd(azimuth) + s_alt*cosd(tilt) );
   I = CleanIrradiance( I, s_alt );
end
