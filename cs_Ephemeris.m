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
   consts;
   % Location

   Latitude  = Location( 1 );
   Longitude = Location( 2 );
   Altitude  = Location( 3 );

    % Time
    d = floor(Time.time); % Get day from double timestamp
    UTCT = 24 * (Time.time - d);  % [hour] Get UTC time
    LST = UTCT + 4*mod(Longitude,360)/60; % [hour] Compute local solar time
    
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
      if ( (cos(HRA_r(j))*tgLatitude < tan(declin_r(j)) && tgLatitude >= 0) || ...
         (cos(HRA_r(j))*tgLatitude > tan(declin_r(j)) && tgLatitude < 0) )
        c_az(j) = -c_az(j);
      end
   end


end
