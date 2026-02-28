
function I = cs_ghi2Ib( GHI, Time, Location, angle )
% GHI: global horizzontal irradiance [W/m^2]
% Time - a struct with the following elements, note that all elements can be
%        column vectors, but they must all be the same length.
% Time.time - column vector of time where the hour of day is normalized
%       between 0 and 1 and the day range from 1 (January 1st) to 366 
%       (December 31th).
%       Example: 4.5 is equal to January 4th, 12.00 A.M.
%
% Location - a vector with the following structure
%       [ latitude, longitude, altitude above the sea level ].
%       latitude - scalar latitude in decimal degrees (positive
%       is the northern hemisphere).
%       longitude - scalar longitude in decimal degrees (positive
%       is west of prime meridian).
%       altitude - optional for this function.
% angle = [ tilt, azimuth ]: panel tilt and azimuth angles [degree]
   consts;
   
   [s_alt, c_alt, s_az, c_az] = cs_Ephemeris( Time, Location );
   [ s_alt, c_alt ] = cs_CleanSunAlt( s_alt, c_alt, s_az, c_az, angle );
   
%   cot_alt = c_alt ./ s_alt;
%   tg_alt = s_alt ./ c_alt;
%   p1 = cot_alt .* s_az;
%   p2 = cot_alt .* c_az;
%   tilt = angle(1);
%   azimuth = angle(2);
%   I = GHI.*( p1*sind(tilt)*sind(azimuth) + p2*sind(tilt)*cosd(azimuth) + tg_alt*cosd(tilt) );

   In = zeros( GHI )
   In( s_alt>0 ) = GHI( s_alt>0 ) ./ ( s_alt( s_alt>0 ) + IN2ID * FLAG_ID );
   I = cs_In2Ib( In, s_alt, c_alt, s_az, c_az, angle ) + In * IN2ID * FLAG_ID;
   I = CleanIrradiance( I, s_alt );
end