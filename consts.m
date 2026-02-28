TORAD = pi/180;                   
DAYSTODEGS = 360/365;              % gradi percorsi dalla terra in un giorno
DAYSTORADS = TORAD * DAYSTODEGS;   % rad percorsi dalla terra in un giorno
CONST_DEC = 23.45 * TORAD;         % max declination angle [rad]
CONST_HRA = 15 * TORAD;           % time zone width [rad]
I0 = 1353;                        %1750 1353 % [w/m^2] solar constant | 1353 - 0.7 | 1750 - 0.6 !
tau0 = 0.7;                        %.6 .7 
IN2ID = 0.1;                     
PA2ATM = 9.86923e-6;              % From Pascal to Atmospheric pressure
ZERO_IRRADIANCE = 1e-4;            % if I < ZER_IRRADIANCE, then I = 0
CLEAN_THRESHOLD = 10;


FLAG_ID = 1; % Itot = Ib + ( Id * FLAG_ID )
