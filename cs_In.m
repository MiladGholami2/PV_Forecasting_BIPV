
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
   consts; 
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
    
   In = zeros( size(invam) );
   for j = 1:length( invam )
      if invam(j) > 0
         In(j) = I0*tau0^(pa*0.678/invam(j));
      end
   end
   In = In.*(In > 1e-4);
   
   Id = IN2ID * In;
   
end
