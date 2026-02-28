clear all

latitude = 44;
longitude = 0;
altitude = 500;

% Time.time - column vector of time where the hour of day is normalized
%       between 0 and 1 and the day range from 1 (January 1st) to 366 
%       (December 31th).
%       Example: 4.5 is equal to January 4th, 12.00 A.M.
Time.time = 4.5; 
Location = [latitude,longitude,altitude];

% Panel orientation
angle = [10,20];

[In, Id, s_alt, c_alt, s_az, c_az ] = cs_In( Time, Location)
I = cs_In2Ib(In, s_alt, c_alt, s_az, c_az, angle)
