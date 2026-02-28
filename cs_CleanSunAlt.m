

function [ s_alt, c_alt ] = cs_CleanSunAlt( s_alt, c_alt, s_az, c_az, angle )
   consts;
   cot_alt = c_alt ./ s_alt;
   azimuth = angle(2);
   
   for i = 1:length( s_alt )
      if cot_alt(i) .* ( cosd(azimuth)*c_az(i) + sind(azimuth)*s_az(i) ) > CLEAN_THRESHOLD & s_alt(i) > 0
         s_alt(i) = -.1;
         c_alt(i) = sqrt( 1 - s_alt(i)^2 );
      end
   end