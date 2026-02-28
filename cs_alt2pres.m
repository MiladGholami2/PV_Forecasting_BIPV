
%                      ------------------------
%                      --- COMPUTE PRESSURE ---
%                      ------------------------
function p = cs_alt2pres( altitude )
   % This function determines site pressure from altitude
   %
   % Description:
   %    This function determines the atmospheric pressure (in Pascals) of a site
   %    on Earth's surface given its altitude (in meters above sea level). Output
   %    "p" is given in Pasclas. "p" is of the same size as altitude.
   %
   % Assumptions include:
   %    Base pressure = 101325 Pa
   %    Temperature at zero altitude = 288.15 K
   %    Gravitational acceleration = 9.80665 m/s^2
   %    Lapse rate = -6.5e-3 K/m
   %    Gas constant for air = 287053 J/(kg*K)
   %    Relative Humidity = 0%
   %
   % Inputs:
   %    altitude - altitude (in meters above sea level)
   %
   % Outputs:
   %    pressure - atmospheric pressure (in Pascals) of a site on Earth's
   %       surface given its altitude
   %
   % Referecens:
   %    "A Quick Derivation relating altitude to air pressure" from Portland
   %    State Aerospace Society, Version 1.03, 12/22/2004.
   consts;
   p = 100 * ( ( 44331.514 - altitude )/11880.516 )^( 1/.1902632 );
end
