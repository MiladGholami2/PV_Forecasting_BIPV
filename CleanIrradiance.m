
function I = CleanIrradiance( I, s_alt )
   consts;
   I = I .* ( I > ZERO_IRRADIANCE ) .* ( s_alt > 0 );
end
