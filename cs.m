TORAD = %pi/180;                   
DAYSTODEGS = 360/365;              % gradi percorsi dalla terra in un giorno
DAYSTORADS = TORAD * DAYSTODEGS;   % rad percorsi dalla terra in un giorno
CONST_DEC = 23.45 * TORAD;         % max declination angle [rad]
CONST_HRA = 15 * TORAD;           % time zone width [rad]
I0 = 1353;                        %1750 1353 % [w/m^2] solar constant | 1353 - 0.7 | 1750 - 0.6 !
tau0 = 0.7;                        %.6 .7 
IN2ID = 0.1;                     
PA2ATM = 9.86923e-6;              % From Pascal to Atmospheric pressure
ZERO_IRRADIANCE = 1e-4;            % if I < ZER_IRRADIANCE, then I = 0


FLAG_ID = 1; % Itot = Ib + ( Id * FLAG_ID )

%I0_06 = 1353; tau0_06 = 0.725; % 1353 .725
%I0_10 = 1300; tau0_10 = 0.75;  % 1300 .75
%I0_15 = 1110; tau0_15 = 0.95;  % 1110 .95

function [In, Id, s_alt, c_alt, s_az, c_az ] = cs_In( Time, Location )
% Compute the normal clear sky irradiance In
% 
% Syntax:
% [ In, Id, s_alt, c_alt, s_az, c_az ] = clearsky( Time, Location )
%
% Input Parameters:
% Time - a struct with the following elements, note that all elements can be
%        column vectors, but they must all be the same length.
% Time.time - column vector of time where the hour of day is normalized
%       between 0 and 1 and the day range from 1 (January 1st) to 366 
%       (December 31th).
%       Example: 4.5 is equal to January 4th, 12.00 A.M.
%
% place: a vector with the following structure
%       [ latitude, longitude, altitude above the sea level ]
%
% LinkeTurbidityInput: an optional input to provide your own Linke turbidity.
%       If this input is omitted, the default Linke turbidity maps will be
%       used. LinkeTurbidityInput may be a scalar or a column vector of Linke
%       turbidities. If scalar is provided, the same turbidity will be used
%       for all time/location sets. If a vector is provided, it must be of the
%       same size as any time/location vectors and each element of the vector
%       corresponds to any time and location elements.
%
% Output:
% In: normal solar irradiance
% Id: diffuse solar irradiance
% s_alt, c_alt: sin and cos of sun altitude [deg]
% s_az, c_az: sin and cos of sun azimuth [deg]
%
    
   Latitude  = Location(1);
   Longitude = Location(2);
   Altitude  = Location(3);
   
   N = length( Time.time );
   
   % Get sun position
   [s_alt, c_alt, s_az, c_az] = cs_Ephemeris( Time, Location );

   % Air Mass
   invam = s_alt;
   
   % Factor of correction due to the atmosphere pressure
   alt = Altitude;
   %pa = exp(-alt/8.2);
   pa = cs_alt2pres( Altitude ) * PA2ATM;
    
   In = zeros( invam );
   for j = 1:length( invam )
      if invam(j) > 0 then
         In(j) = I0*tau0^(pa*0.678/invam(j));
      end
   end
   In = In.*(In > 1e-4);
   
   Id = IN2ID * In;
   
end

%                         --------------------------
%                         --- POSIZIONE DEL SOLE ---
%                         --------------------------
function [s_alt, c_alt, s_az, c_az] = cs_Ephemeris( Time, Location )
   % This function calculates the position of the sun given time, location,
   % and optionally pressure and temperature
   % 
   % Syntax
   %    [s_alt, c_alt, s_az, c_az]=pvl_ephemeris(Time, Location)
   %
   % Description  
   %  [s_alt, c_alt, s_az, c_az]=pvl_ephemeris(Time, Location)
   %      Uses the given time and location structs to give sun positions
   %
   % Input Parameters:
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
   %
   % Output Parameters:
   % s_alt, c_alt: sin and cos of sun altitude [deg]
   % s_az, c_az: sin and cos of sun azimuth [deg]
   %

   % Location
   Latitude  = Location( 1 );
   Longitude = Location( 2 );
   Altitude  = Location( 3 );

    % Time
    d = int(Time.time); % Get day from double timestamp
    UTCT = 24 * (Time.time - d);  % [hour] Get UTC time
    LST = UTCT + 4*modulo(Longitude,360)/60; % [hour] Compute local solar time
    
    omega_h_r = DAYSTORADS*(d - 81 + ((LST-12)/24)); % [rad] day angle
    declin_r  = CONST_DEC * sin(omega_h_r); % [rad] declination angle
    EoT = 9.87*sin(2*omega_h_r) - 7.53*cos(omega_h_r) - 1.5*sin(omega_h_r); % [min] Equation of Time
    LST = LST +  EoT/60; % [hour] Local Solar Time
    HRA_r = CONST_HRA*(LST - 12); % [rad] hour angle
    
    % Sun altitude
    latitude_r  = TORAD*Latitude; % [rad]
    s_alt       = sin(latitude_r).*sin(declin_r)+cos(latitude_r).*cos(declin_r).*cos(HRA_r);
    c_alt       = sqrt(1 - s_alt.^2);
    
    % Sun azimut
    s_az        = cos(declin_r).*sin(HRA_r)./c_alt;
    c_az        = sqrt(1-s_az.^2);
    
    tgLatitude  = tan(latitude_r);
    for j = 1:length(Time.time)
        if (cos(HRA_r(j))*tgLatitude < tan(declin_r(j)) & tgLatitude >= 0) | (cos(HRA_r(j))*tgLatitude > tan(declin_r(j)) & tgLatitude < 0) then
            c_az(j) = -c_az(j);
        end
    end

end

%                       ------------------------------
%                       --- CAST FROM GHI/IN TO IB ---
%                       ------------------------------

function I = cs_In2Ib(In, s_alt, c_alt, s_az, c_az, angle)
% In: normal irradiance [W/m^2]
% s_alt, c_alt, s_az, c_az: sin and cos of sun altitude and azimuth angles [degree]
% angle = [ tilt, azimuth ]: panel tilt and azimuth angles [degree]
   p1 = c_alt.*s_az;
   p2 = c_alt.*c_az;
   tilt = angle(1);
   azimuth = angle(2);
   
   I = In.*( p1*sind(tilt)*sind(azimuth) + p2*sind(tilt)*cosd(azimuth) + s_alt*cosd(tilt) );
   I = CleanIrradiance( I, s_alt );
end

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

function thIcs = cs_clearskyOnSurface( Time, Location, angle )

   [In, Id, s_alt, c_alt, s_az, c_az ] = cs_In( Time, Location )
   thIcs = cs_In2Ib( In, s_alt, c_alt, s_az, c_az, angle ) + ( Id * FLAG_ID );
   
end

CLEAN_THRESHOLD = 10;
function [ s_alt, c_alt ] = cs_CleanSunAlt( s_alt, c_alt, s_az, c_az, angle )
   
   cot_alt = c_alt ./ s_alt;
   azimuth = angle(2);
   
   for i = 1:length( s_alt )
      if cot_alt(i) .* ( cosd(azimuth)*c_az(i) + sind(azimuth)*s_az(i) ) > CLEAN_THRESHOLD & s_alt(i) > 0
         s_alt(i) = -.1;
         c_alt(i) = sqrt( 1 - s_alt(i)^2 );
      end
   end
   
end

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
   
   p = 100 * ( ( 44331.514 - altitude )/11880.516 )^( 1/.1902632 );
end

function I = CleanIrradiance( I, s_alt )
   I = I .* ( I > ZERO_IRRADIANCE ) .* ( s_alt > 0 );
end
