
clearvars; close all; clc

%% ====================== USER OPTIONS ======================
useMeasuredTruth = false;     % true: use S.measure.P as truth for BOTH modes
usePresetPV      = true;      % no interactive input
thrFracNight     = 0.07;      % threshold for night-ish removal (on POA_cs)

% ---- ML options (set L=0 to remove AR advantage) ----
cfgML = struct();
cfgML.L             = 3;      % 0 = no past power lags (fairest vs LP)
cfgML.gbmNumCycles   = 600;
cfgML.gbmLearnRate   = 0.05;
cfgML.ridgeLambda    = 1e-2;
cfgML.verbose        = true;
cfgML.rngSeed        = 42;

%% ====================== LOCATION ======================
lat = 39.5013;
lon = -8.7677;
alt = 94;
Location = [lat, lon, alt];

%% ====================== LOAD DATASET ======================
matfile = 'dataSetSardegna-DC-02.mat';
S = load(matfile);

% ---- timestamps (UTC) ----
yr      = S.measure.time.year(:);
doyFrac = S.measure.time.time(:);
t = datetime(yr,1,1,0,0,0,'TimeZone','UTC') + days(doyFrac - 1); % Convert it into a real UTC datetime vector.
t = datetime(t,'Format','dd-MMM-yyyy HH:mm:ss','TimeZone','UTC');
t = dateshift(t,'start','second');
% output t:
%t =
  % 02-Feb-2012 00:00:00
  % 02-Feb-2012 00:15:00
  % 02-Feb-2012 00:30:00
  % 02-Feb-2012 00:45:00
  % 02-Feb-2012 01:00:00
  % ...

% ---- signals ----
DNI_meas = S.measure.I(:);
Ta_meas  = S.measure.T(:);
Pmeas    = S.measure.P(:);

DNI_fcst = S.forecast.I(:);
Ta_fcst  = S.forecast.T(:);

% ---- timetables ----
TT_meas = timetable(t, DNI_meas, Ta_meas, Pmeas, 'VariableNames', {'DNI','T2M','PMEAS'});
TT_fcst = timetable(t, DNI_fcst, Ta_fcst, Pmeas, 'VariableNames', {'DNI','T2M','PMEAS'});

TT_meas = sortrows(TT_meas);
TT_fcst = sortrows(TT_fcst);

% remove duplicates consistently
[~, ia] = unique(TT_meas.Properties.RowTimes, 'stable');
TT_meas = TT_meas(ia,:);
TT_fcst = TT_fcst(ia,:);

% regularize to 15-min grid
TT15_meas = retime(TT_meas, 'regular', 'pchip', 'TimeStep', minutes(15));
TT15_fcst = retime(TT_fcst, 'regular', 'pchip', 'TimeStep', minutes(15));

rt = TT15_meas.Properties.RowTimes;

Tmeas = table(rt, TT15_meas.DNI, TT15_meas.T2M, TT15_meas.PMEAS, ...
    'VariableNames', {'Time','DNI','T2M','PMEAS'});

Tfcst = table(rt, TT15_fcst.DNI, TT15_fcst.T2M, TT15_fcst.PMEAS, ...
    'VariableNames', {'Time','DNI','T2M','PMEAS'});

fprintf("Dataset window: %s → %s | rows=%d\n", datestr(rt(1)), datestr(rt(end)), numel(rt));

%% ====================== TRAIN / VAL SPLIT (paper) ======================
tTrainStart = datetime(2012,2,2,0,0,0,'TimeZone','UTC');
tTrainEnd   = datetime(2012,4,1,23,59,59,'TimeZone','UTC');

isTrain = (rt >= tTrainStart) & (rt <= tTrainEnd);
isVal   = (rt >  tTrainEnd);

assert(any(isTrain) && any(isVal), 'Train/Val split produced empty sets.');

fprintf('Split: TRAIN %s → %s | VAL %s → %s\n', ...
    datestr(min(rt(isTrain))), datestr(max(rt(isTrain))), ...
    datestr(min(rt(isVal))),   datestr(max(rt(isVal))));

%% ====================== PV CONFIG ======================

%% ====================== Per-PV CONFIGURATION ===========================
albedo = 0.20;     % ground reflectance

usePreset = input('Use preset 5-PV configuration? (y/n): ', 's');
usePreset = ~isempty(usePreset) && (lower(usePreset(1))=='y');

% Compatibility with other script variants
usePresetPV = usePreset;

if usePreset
    % ===== 5 PVs with different orientations =====
    % Convention: az_deg 0°=South, East negative, West positive

    % num_pvs    = 5;
    % 
    % tilt_deg   = [90, 30,  90, 45, 25];
    % az_deg     = [-85, -70,  -45, 45, 80];
    % 
    % kw_dc_arr  = [3.5, 6.5, 3, 4, 2.5];
    % losses_pct = [14, 14, 14, 14, 14];
    % inv_eff    = [96, 96, 96, 96, 96];
    % dcac_ratio = [1.1, 1.1, 1.1, 1.1];
    % mod_type   = [0, 0, 0, 0, 0];

   num_pvs = 10;

    tilt_deg   = [90,   30,   90, 45, 25,  20,  80,  40  40, 80];
    az_deg     = [-85, -70,  -45, 45, 80,  10, -20, -60, 20, 20];
    kw_dc_arr  = [3.5,  6.5,  3,  4,  2.5, 3.2, 4.5, 5.5, 6, 5];
% -----------------------------
% Nominal DC ratings [kW]
% -----------------------------
               % flat/carport

    losses_pct = [14, 14, 14, 14, 14, 14, 14, 14, 14, 14];
    inv_eff    = [96, 96, 96, 96, 96, 96, 96, 96, 96, 96 ];
    dcac_ratio = [1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1,1, 1.1];
    mod_type   = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    fprintf('Using preset with %d PV systems.\n', num_pvs);
    % ===== perturb PV3 mounting angles test (Gianni's suggestion) =====
pertList = [ ...
    2 -2 ];

baseTilt3 = tilt_deg(3);
baseAz3   = az_deg(3);
else
    num_pvs = input('Enter number of PV systems to simulate (e.g., 5): ');
    tilt_deg   = zeros(1,num_pvs);
    az_deg     = zeros(1,num_pvs);
    kw_dc_arr  = zeros(1,num_pvs);
    losses_pct = zeros(1,num_pvs);
    inv_eff    = zeros(1,num_pvs);
    dcac_ratio = zeros(1,num_pvs);
    mod_type   = zeros(1,num_pvs);
end

%% ====================== RUN BOTH MODES ======================
Modes = {'measured','forecast'};



    % apply perturbation (PV3)
    tilt_deg(3) = baseTilt3 ;
    az_deg(3)   = baseAz3;

    R = struct();   % reset results for this perturbation (optional)
    for rr = 1:numel(Modes)
    mode = Modes{rr};
    fprintf('\n==================== MODE: %s ====================\n', upper(mode));

    if strcmp(mode,'measured')
        T = Tmeas;
    else
        T = Tfcst;
    end

    nT = height(T);

    %% ===== Clear-sky DNI + geometry (cs_In) =====
    DNI_cs_my = zeros(nT,1);
    s_alt = zeros(nT,1); c_alt = zeros(nT,1);
    s_az  = zeros(nT,1); c_az  = zeros(nT,1);
    gamma_rad = zeros(nT,1);

    for k = 1:nT
        tUTC = T.Time(k);
        doy  = day(tUTC, 'dayofyear');
        frac = hour(tUTC) + minute(tUTC)/60 + second(tUTC)/3600;
        TimeStruct.time = doy + frac/24;

        [In, ~, s_alt(k), c_alt(k), s_az(k), c_az(k)] = cs_In(TimeStruct, Location);
        DNI_cs_my(k) = In;
        gamma_rad(k) = atan2(s_az(k), c_az(k));
    end
     

   % s_alt = sin(solar altitude angle)
   % Solar altitude = angle of the sun above the horizon
   % altitude > 0° → sun above horizon → day
   % altitude = 0° → sunrise/sunset
   % altitude < 0° → sun below horizon → night
    isDay = (s_alt > 0);

    DNI_act = T.DNI;
    DNI_act(~isDay) = 0;

    % Mode-dependent ambient temperature used for "physics"/LP & for ML prediction stage
    Ta = T.T2M;

    % Forecast temperature used for ML TRAIN stage (your request)
    Ta_tr = Tfcst.T2M;      % always forecast temp, same timestamps
    Ta_pr = Ta;             % prediction temp: measured in measured-mode, forecast in forecast-mode

    %% ===== PV loops: POA + PVWatts-like DC power =====
    pv_POA_act = zeros(nT, num_pvs);
    pv_POA_cs  = zeros(nT, num_pvs);
    pv_P_dc    = zeros(nT, num_pvs);
    pv_P_dc_cs = zeros(nT, num_pvs);

    for pv = 1:num_pvs
        switch mod_type(pv)
            case 0, gamma = -0.0047; NOCT = 45;
            case 1, gamma = -0.0035; NOCT = 44;
            case 2, gamma = -0.0020; NOCT = 46;
            otherwise, gamma = -0.0047; NOCT = 45;
        end

        psi = deg2rad(tilt_deg(pv));
        xi  = deg2rad(az_deg(pv));

        sin_h = s_alt;  cos_h = c_alt;
        cos_alpha = sin(psi).*cos_h .* cos(xi - gamma_rad) + cos(psi).*sin_h;
        cos_alpha(~isfinite(cos_alpha)) = 0;  % cos_alpha is NaN/Inf → set it to 0 (meaning “no effective sun on the plane”).
        % If the sun is “behind” the panel (incidence angle > 90°), the cosine is negative.
        % Physically, irradiance on the front of the plane can’t be negative; it should be 0 in that case
        cos_alpha = max(cos_alpha, 0);

        POA_act = max(DNI_act   .* cos_alpha, 0);
        POA_cs  = max(DNI_cs_my .* cos_alpha, 0);

        Pdc_rated_W = kw_dc_arr(pv) * 1;

        % ===== FIXED: use mode-dependent DNI_act (NOT Tmeas.DNI) =====
        Tcell_act = Tmeas.T2M + ( max((Tmeas.DNI)   .* cos_alpha, 0)/800) * (NOCT - 20);
        Pdc_act   = Pdc_rated_W .* ( max((Tmeas.DNI)   .* cos_alpha, 0)/1000) .* (1 + gamma.*(Tcell_act - 25));

        Tcell_cs  = Ta + (POA_cs/800) * (NOCT - 20);
        Pdc_cs    = Pdc_rated_W .* (POA_cs/1000) .* (1 + gamma.*(Tcell_cs - 25));

         % Negative power can appear because of the temperature factor (1 + gamma*(Tcell-25)),
         % noise, or interpolation artifacts. Physically, PV DC output can’t be negative
        Pdc_act = max(Pdc_act,0); Pdc_act(~isDay)=0;
        Pdc_cs  = max(Pdc_cs,0);  Pdc_cs(~isDay)=0;

        pv_POA_act(:,pv) = POA_act;
        pv_POA_cs(:,pv)  = POA_cs;
        pv_P_dc(:,pv)    = Pdc_act;
        pv_P_dc_cs(:,pv) = Pdc_cs;
    end

    %% ===== Truth definition =====
    if useMeasuredTruth && any(isfinite(T.PMEAS))
        Ptot_true = T.PMEAS;
        fprintf("Truth: using measured power (measure.P) in both modes.\n");
    else
        Ptot_true = sum(pv_P_dc, 2);
        fprintf("Truth: using simulated sum DC power (mode-consistent).\n");
    end

    %% ====================== LP (CS envelope) ======================
    Mpv = num_pvs;
    A_all = zeros(nT, 3*Mpv);
    A_cs  = zeros(nT, 3*Mpv);

    for p = 1:Mpv
        ix = (p-1)*3 + (1:3);
        Ii  = pv_POA_act(:,p);
        Iic = pv_POA_cs(:,p);

        A_all(:,ix(1)) = Ii;
        A_all(:,ix(2)) = Ii.^2;
        A_all(:,ix(3)) = Ii .* Ta(:);

        A_cs(:,ix(1))  = Iic;
        A_cs(:,ix(2))  = Iic.^2;
        A_cs(:,ix(3))  = Iic .* Tfcst.T2M(:);
    end

    % night-ish removal: all PVs below their own thresholds
    Pthr_vec = max(pv_POA_cs,[],1) * thrFracNight;
    bad_idx = true(nT,1);
    for p = 1:Mpv
        bad_idx = bad_idx & (pv_POA_cs(:,p) < Pthr_vec(p));
    end
    mask_train_cs = isTrain & ~bad_idx;

    [theta_lp, ~, ~] = solve_LP(A_cs(mask_train_cs,:), Ptot_true(mask_train_cs));
    Ptot_lp_full = max(A_all * theta_lp, 0);
    p=3; ix=(p-1)*3+(1:3);
X = A_cs(mask_train_cs, ix);
fprintf('PV3 A_cs max = [%g %g %g]\n', max(X,[],1));
fprintf('PV3 A_cs std = [%g %g %g]\n', std(X,0,1));
fprintf('PV3 POA_cs max/std = %g / %g\n', max(pv_POA_cs(mask_train_cs,p)), std(pv_POA_cs(mask_train_cs,p)));

%pv_P_dc(:,3)- pv_P_dc(:,)

    mu_LP = reshape(theta_lp, 3, Mpv);
    fprintf('\nLP μ coefficients:\n');
    for p = 1:Mpv
        fprintf('PV%-2d:  mu1 = %+ .6e   mu2 = %+ .6e   mu3 = %+ .6e\n', ...
            p, mu_LP(1,p), mu_LP(2,p), mu_LP(3,p));
    end

    % per-PV LP
    Ppv_lp = zeros(nT, Mpv);
    for p = 1:Mpv
        Ii = pv_POA_act(:,p);
        Ppv_lp(:,p) = mu_LP(1,p).*Ii + mu_LP(2,p).*Ii.^2 + mu_LP(3,p).*Ii.*Ta(:);
    end
    Ppv_lp = max(Ppv_lp, 0);

    %% ====================== ML (YOUR REQUEST: forecast Ta in TRAIN) ======================
    % Train on:  POA_cs + forecast Ta (Ta_tr)
   % --- choose training temperature = forecast temperature (your request)
Ta_tr = Tfcst.T2M;   % always forecast temp, aligned to same rt
Ta_pr = T.T2M;       % prediction temp: measured in measured-mode, forecast in forecast-mode

% --- ML (ARX features per paper)
[yhat_full_gbm, yhat_full_ridge, mdlML, metricsValML, infoML] = ...
    solve_ML_ARX_POA_sum_dual( ...
        T.Time, ...
        Ta_tr(:), Ta_pr(:), ...
        pv_POA_cs, pv_POA_act, ...
        Ptot_true(:), ...
        mask_train_cs, isVal, cfgML);

yhat_gbm   = yhat_full_gbm;
yhat_ridge = yhat_full_ridge;


    %% ====================== Metrics (VAL) ======================
  %% ====================== Metrics (VAL) — FULL SET ======================
Pm_val = Ptot_true(isVal);                  % reference on VAL
Pnom   = sum(kw_dc_arr) * 1;             % nominal plant DC power [W]

% LP
Ph_lp_val = Ptot_lp_full(isVal);
M_lp = compute_metrics_full(Pm_val, Ph_lp_val, Pnom);
fprintf(['LP   Validation (VAL) — RMSE: %.3f kW | MAE: %.3f kW | MBE: %.3f kW | ' ...
         'MAPE: %.3f %% | NRMSE: %.6f | R^2: %.6f | RMSE_NP: %.6f | MAPE_NP: %.6f | K=%d\n'], ...
         M_lp.rmse, M_lp.mae, M_lp.mbe, M_lp.mape, M_lp.nrmse, M_lp.r2, M_lp.rmse_np, M_lp.mape_np, M_lp.K);

% ML (GBM)
Ph_gbm_val = yhat_gbm(isVal);
M_gbm = compute_metrics_full(Pm_val, Ph_gbm_val, Pnom);
fprintf(['GBM  Validation (VAL) — RMSE: %.3f kW | MAE: %.3f kW | MBE: %.3f kW | ' ...
         'MAPE: %.3f %% | NRMSE: %.6f | R^2: %.6f | RMSE_NP: %.6f | MAPE_NP: %.6f | K=%d\n'], ...
         M_gbm.rmse, M_gbm.mae, M_gbm.mbe, M_gbm.mape, M_gbm.nrmse, M_gbm.r2, M_gbm.rmse_np, M_gbm.mape_np, M_gbm.K);

% ML (Ridge)
Ph_rid_val = yhat_ridge(isVal);
M_rid = compute_metrics_full(Pm_val, Ph_rid_val, Pnom);
fprintf(['Ridge Validation (VAL) — RMSE: %.3f kW | MAE: %.3f W | MBE: %.3f kW | ' ...
         'MAPE: %.3f %% | NRMSE: %.6f | R^2: %.6f | RMSE_NP: %.6f | MAPE_NP: %.6f | K=%d\n'], ...
         M_rid.rmse, M_rid.mae, M_rid.mbe, M_rid.mape, M_rid.nrmse, M_rid.r2, M_rid.rmse_np, M_rid.mape_np, M_rid.K);



    %% ====================== Save to struct ======================
    R.(mode).Time    = T.Time;
    R.(mode).DNI     = T.DNI;
    R.(mode).Ta      = Ta;

    R.(mode).DNI_cs  = DNI_cs_my;
    R.(mode).isDay   = isDay;

    R.(mode).POAact  = pv_POA_act;
    R.(mode).POAcs   = pv_POA_cs;

    R.(mode).pv_P_dc = pv_P_dc;
    R.(mode).Ptrue   = Ptot_true;

    R.(mode).Plp     = Ptot_lp_full;
    R.(mode).mu_LP   = mu_LP;
    R.(mode).Ppv_lp  = Ppv_lp;

    R.(mode).Pml_gbm   = yhat_gbm;
    R.(mode).Pml_ridge = yhat_ridge;
    R.(mode).mdlML     = mdlML;
    R.(mode).metricsML = metricsValML;

 R.(mode).rmse_lp   = M_lp.rmse;
R.(mode).mae_lp    = M_lp.mae;

R.(mode).rmse_gbm  = M_gbm.rmse;
R.(mode).mae_gbm   = M_gbm.mae;

R.(mode).rmse_rid  = M_rid.rmse;
R.(mode).mae_rid   = M_rid.mae;

% Save (optional)
    R.(mode).metricsFull.LP    = M_lp;
    R.(mode).metricsFull.GBM   = M_gbm;
    R.(mode).metricsFull.Ridge = M_rid;
    end % end rr (mode loop)



%% ====================== PLOTS (unchanged from your script) ======================
fs = 22;
colorsPV = lines(max(num_pvs,1));

dataYear = year(R.measured.Time(find(isTrain,1,'first')));

% TRAIN plot window Feb 02–17
tTrainPlotStart = datetime(dataYear,2,2,0,0,0,'TimeZone','UTC');
tTrainPlotEnd   = datetime(dataYear,2,17,23,59,59,'TimeZone','UTC');
idxTrainPlot = (R.measured.Time >= tTrainPlotStart) & (R.measured.Time <= tTrainPlotEnd);

% VAL plot window Apr 16–May 01
tValPlotStart = datetime(dataYear,4,16,0,0,0,'TimeZone','UTC');
tValPlotEnd   = datetime(dataYear,4,22,23,59,59,'TimeZone','UTC');
idxValPlot = (R.measured.Time >= tValPlotStart) & (R.measured.Time <= tValPlotEnd);

% short VAL window Apr 16–19
tValShortStart = datetime(dataYear,5,16,0,0,0,'TimeZone','UTC');
tValShortEnd   = datetime(dataYear,4,22,23,59,59,'TimeZone','UTC');
idxValShort = (R.measured.Time >= tValShortStart) & (R.measured.Time <= tValShortEnd);
dayTicks = (dateshift(tValShortStart,'start','day') : days(1) : dateshift(tValShortEnd,'start','day')).';

% ---------- Fig A: TRAIN meteo comparison (DNI + Ta) ----------
figure('Name','Fig A: TRAIN Meteo (DNI & Ta) measured vs forecast','Position',[100 750 1600 650]);
tiledlayout(1,1,'Padding','compact','TileSpacing','compact');

 hold on; grid on;
stairs(R.measured.Time(idxTrainPlot), R.measured.Ta(idxTrainPlot), 'b-','LineWidth',2.0);
stairs(R.forecast.Time(idxTrainPlot), R.forecast.Ta(idxTrainPlot), 'r-','LineWidth',2.0);
ylabel('Ta [$^\circ$C]','Interpreter','latex','FontSize',fs);
legend({'$T_a$','$\tilde{T}_a$'},'Interpreter','latex','FontSize',fs,'Location','best');
ax=gca; ax.FontSize=fs; ax.TickLabelInterpreter='latex'; ax.XAxis.TickLabelFormat='MMM dd';
set(gcf,'Color','w');

% ---------- Fig 1: TRAIN total power comparison ----------
% figure('Name','Fig 1: TRAIN Ptot_true measured vs forecast','Position',[100 300 1500 420]);
% clf; hold on; grid on;
% stairs(R.measured.Time(idxTrainPlot), R.measured.Ptrue(idxTrainPlot), 'b-','LineWidth',2.2);
% stairs(R.forecast.Time(idxTrainPlot), R.forecast.Ptrue(idxTrainPlot), 'r-','LineWidth',2.2);
% ylabel('Power [W]','Interpreter','latex','FontSize',fs);
% legend({'$P_{\mathrm{tot}}$','$\tilde{P}_{\mathrm{tot}}$'},'Interpreter','latex','FontSize',fs,'Location','best');
% ax=gca; ax.FontSize=fs; ax.TickLabelInterpreter='latex'; ax.XAxis.TickLabelFormat='MMM dd';
% set(gcf,'Color','w');



% ---------- Fig 3: VAL Truth vs LP vs ML (per mode) ----------
figure('Name','Fig 3: VAL Truth vs LP vs ML (each mode)','Position',[100 850 1500 420]);
%tiledlayout(2,1,'Padding','compact','TileSpacing','compact');

hold on; grid on;
stairs(R.measured.Time(idxValPlot), R.measured.Ptrue(idxValPlot), 'b-','LineWidth',2.0,'DisplayName','Measured');
stairs(R.measured.Time(idxValPlot), R.measured.Plp(idxValPlot),   'r-','LineWidth',2.0,'DisplayName','CSIP');
stairs(R.measured.Time(idxValPlot), R.measured.Pml_gbm(idxValPlot),'k-','LineWidth',2.0,'DisplayName','ARX--GBDT');
stairs(R.measured.Time(idxValPlot), R.measured.Pml_ridge(idxValPlot),'g-','LineWidth',2.0,'DisplayName','ARX--Ridge');
%title('Measured-mode','Interpreter','latex','FontSize',fs);
ylabel('Power [kW]','Interpreter','latex','FontSize',26);
legend('show','Interpreter','latex','FontSize',fs,'Location','best');



ax=gca;
ax.FontSize = 26;
ax.TickLabelInterpreter = 'latex';
ax.XAxis.TickLabelFormat = 'MMM dd';
ax.XAxis.SecondaryLabel.String = '';
ylim([0 40]);
set(gcf,'Color','w');

figure('Name','Fig 3: VAL Truth vs LP vs ML (each mode)','Position',[100 850 1500 420]);
%tiledlayout(2,1,'Padding','compact','TileSpacing','compact');
 hold on; grid on;
stairs(R.forecast.Time(idxValPlot), R.forecast.Ptrue(idxValPlot), 'b-','LineWidth',2.0,'DisplayName','Measured');
stairs(R.forecast.Time(idxValPlot), R.forecast.Plp(idxValPlot),   'r-','LineWidth',2.0,'DisplayName','CSIP');
stairs(R.forecast.Time(idxValPlot), R.forecast.Pml_gbm(idxValPlot),'k-','LineWidth',2.0,'DisplayName','ARX--GBDT');
stairs(R.forecast.Time(idxValPlot), R.forecast.Pml_ridge(idxValPlot),'g-','LineWidth',2.0,'DisplayName','ARX--Ridge');
%title('Forecast-mode','Interpreter','latex','FontSize',fs);
ylabel('Power [kW]','Interpreter','latex','FontSize',26);
legend('show','Interpreter','latex','FontSize',fs,'Location','best');

ax=gca;
ax.FontSize = 26;
ax.TickLabelInterpreter = 'latex';
ax.XAxis.TickLabelFormat = 'MMM dd';
ax.XAxis.SecondaryLabel.String = '';
ylim([0 40]);
set(gcf,'Color','w');







%% ====================== FINAL METRICS PRINT ======================
fprintf('\n=== FINAL METRICS (VAL) ===\n');
fprintf('MEASURED mode:\n');
fprintf('  LP    : RMSE=%.3f kW | MAE=%.3f W\n', R.measured.rmse_lp,  R.measured.mae_lp);
fprintf('  ML GBM: RMSE=%.3f kW | MAE=%.3f W\n', R.measured.rmse_gbm, R.measured.mae_gbm);
fprintf('  ML Rid: RMSE=%.3f kW | MAE=%.3f W\n', R.measured.rmse_rid, R.measured.mae_rid);

fprintf('FORECAST mode:\n');
fprintf('  LP    : RMSE=%.3f kW | MAE=%.3f W\n', R.forecast.rmse_lp,  R.forecast.mae_lp);
fprintf('  ML GBM: RMSE=%.3f kW | MAE=%.3f W\n', R.forecast.rmse_gbm, R.forecast.mae_gbm);
fprintf('  ML Rid: RMSE=%.3f kW | MAE=%.3f W\n', R.forecast.rmse_rid, R.forecast.mae_rid);

fprintf('\nDone.\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% LOCAL FUNCTION: LP solve
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [mu_est,P_cs_est,obj_value] = solve_LP(A_cs,P)

    yalmip('clear')
    [~,k] = size(A_cs);
    theta = sdpvar(k,1);
    P_cs_est = A_cs * theta;

    Objective   = sum(P_cs_est - P);
    Constraints = [P <= P_cs_est];

    % =====================================================
    % Physical constraints
    % =====================================================

    Mpv = k/3;                 % number of PVs
    eps_mu1 = 1e-6;            % small positive lower bound

    % bounds from paper
    eta2_min = -2.5e-4;
    eta2_max = -1.9e-5;
    eta3_min = -4.8e-3;
    eta3_max = -1.7e-3;

    for p = 1:Mpv
        i1 = (p-1)*3 + 1;   % mu1 index
        i2 = i1 + 1;        % mu2
        i3 = i1 + 2;        % mu3

        mu1 = theta(i1);
        mu2 = theta(i2);
        mu3 = theta(i3);

        % mu1 > 0
        Constraints = [Constraints, mu1 >= eps_mu1];

        % eta2 bounds:  eta2_min <= mu2/mu1 <= eta2_max
        Constraints = [Constraints, ...
            mu2 >= eta2_min * mu1, ...
            mu2 <= eta2_max * mu1];

        % eta3 bounds:  eta3_min <= mu3/mu1 <= eta3_max
        Constraints = [Constraints, ...
            mu3 >= eta3_min * mu1, ...
            mu3 <= eta3_max * mu1];
    end

    % =====================================================

    ops = sdpsettings('solver','gurobi','verbose',1,'cachesolvers',1, ...
                      'savesolverinput',1,'savesolveroutput',1);

    sol = optimize(Constraints,Objective,ops);

    if sol.problem ~= 0
        disp('Error in solving the problem!');
        mu_est   = nan(size(theta));
        P_cs_est = nan(size(P_cs_est));
        obj_value= nan;
        return
    end

    mu_est   = value(theta);
    P_cs_est = value(P_cs_est);
    obj_value= value(Objective);
end



function [yhat_full_gbm, yhat_full_ridge, mdl, metrics, info] = ...
    solve_ML_ARX_POA_sum_dual(time, Ta_tr, Ta_pr, POA_cs, POA_pr, y, isTrain, isVal, S)
% TRAIN:
%   z(t) = [ y(t-1..t-L), Ics_sum(t), dIcs(t), Ta_tr(t) ]
% VAL/PRED:
%   z(t) = [ yhat(t-1..t-L), Ipr_sum(t), dIpr(t), Ta_pr(t) ]
% where yhat lags are obtained by recursive roll-out.

% ---------------- Defaults ----------------
D.L             = 3;
D.gbmNumCycles  = 600;
D.gbmLearnRate  = 0.05;
D.ridgeLambda   = 1e-2;
D.verbose       = true;
D.rngSeed       = 42;

if nargin >= 9 && ~isempty(S)
    f = fieldnames(S);
    for k=1:numel(f)
        if isfield(D,f{k}), D.(f{k}) = S.(f{k}); end
    end
end
rng(D.rngSeed);

time    = time(:);
Ta_tr   = Ta_tr(:);
Ta_pr   = Ta_pr(:);
y       = y(:);
isTrain = isTrain(:);
isVal   = isVal(:);

[nT, Mpv] = size(POA_cs);
assert(all(size(POA_pr)==[nT,Mpv]), 'POA_pr must match POA_cs size.');
assert(numel(Ta_tr)==nT && numel(Ta_pr)==nT && numel(y)==nT, 'Size mismatch.');

% ---------------- Aggregate irradiance ----------------
Ics_sum = sum(POA_cs, 2);
Ipr_sum = sum(POA_pr, 2);

dIcs = [nan; diff(Ics_sum)];
dIpr = [nan; diff(Ipr_sum)];

% ---------------- TRAIN AR lags from TRUE y ----------------
L = D.L;
Ylags_tr = nan(nT, L);
for ell = 1:L
    Ylags_tr(:,ell) = [nan(ell,1); y(1:end-ell)];
end

Ztr_raw = [Ylags_tr, Ics_sum, dIcs, Ta_tr];

valid_tr = all(isfinite(Ztr_raw),2) & isfinite(y);
tr = isTrain & valid_tr;
assert(any(tr), 'No valid training rows for ML.');

Ztr = Ztr_raw(tr,:);
ytr = y(tr);

% ---------------- Standardize on TRAIN only ----------------
muZ = mean(Ztr,1,'omitnan');
sgZ = std(Ztr,0,1,'omitnan');  sgZ(sgZ==0)=1;

Ztr_hat = (Ztr - muZ)./sgZ;

% ---------------- Train models ----------------
% ---- Ridge with intercept (unpenalized) ----
lambda = D.ridgeLambda;
d = size(Ztr_hat,2);

Xtr = [ones(size(Ztr_hat,1),1), Ztr_hat];
Reg = diag([0; ones(d,1)]);
beta = (Xtr.'*Xtr + lambda*Reg) \ (Xtr.'*ytr);

% ---- GBDT ----
mdl_gbm = fitrensemble(Ztr_hat, ytr, ...
    'Method','LSBoost', ...
    'NumLearningCycles', D.gbmNumCycles, ...
    'LearnRate', D.gbmLearnRate);

% ---------------- VALIDATION: recursive rollout ----------------
va_idx = find(isVal);
yhat_full_gbm   = nan(nT,1);
yhat_full_ridge = nan(nT,1);

% initial lag buffer what:
% use last available TRUE y before validation starts (if exists)
t0 = va_idx(1);
lagbuf = nan(1,L);
for ell=1:L
    k0 = t0-ell;
    if k0 >= 1 && isfinite(y(k0))
        lagbuf(ell) = y(k0);
    else
        lagbuf(ell) = 0; % fallback if boundary missing
    end
end

for kk = 1:numel(va_idx)
    t = va_idx(kk);

    % require exogenous features
    if ~isfinite(Ipr_sum(t)) || ~isfinite(dIpr(t)) || ~isfinite(Ta_pr(t))
        continue
    end

    % build raw feature row using predicted lags
    z_raw = [lagbuf, Ipr_sum(t), dIpr(t), Ta_pr(t)];

    if ~all(isfinite(z_raw))
        continue
    end

    % standardize
    z_hat = (z_raw - muZ)./sgZ;

    % Ridge prediction
    x_hat = [1, z_hat];
    y_r = x_hat * beta;

    % GBM prediction
    y_g = predict(mdl_gbm, z_hat);

    % clamp
    y_r = max(y_r, 0);
    y_g = max(y_g, 0);

    yhat_full_ridge(t) = y_r;
    yhat_full_gbm(t)   = y_g;

    % update lag buffer with RIDGE or GBM?
    % choose ONE closed-loop source. Usually ridge is more stable; use ridge:
    if L > 0
        lagbuf = [y_r, lagbuf(1:end-1)];
    end
end

% ---------------- Metrics computed only where we have predictions ----------
va_valid_r = isVal & isfinite(yhat_full_ridge) & isfinite(y);
va_valid_g = isVal & isfinite(yhat_full_gbm)   & isfinite(y);

yr = y(va_valid_r); pr = yhat_full_ridge(va_valid_r);
yg = y(va_valid_g); pg = yhat_full_gbm(va_valid_g);

metrics.rmse_val_ridge = sqrt(mean((yr-pr).^2,'omitnan'));
metrics.mae_val_ridge  = mean(abs(yr-pr),'omitnan');
metrics.rmse_val_gbm   = sqrt(mean((yg-pg).^2,'omitnan'));
metrics.mae_val_gbm    = mean(abs(yg-pg),'omitnan');

if D.verbose
    fprintf('[ML ARX-rollout] L=%d | Train=%d | Val(Ridge)=%d Val(GBM)=%d | Ridge RMSE=%.3fW GBM RMSE=%.3fW\n', ...
        L, sum(tr), sum(va_valid_r), sum(va_valid_g), metrics.rmse_val_ridge, metrics.rmse_val_gbm);
end

mdl = struct('gbm', mdl_gbm, 'ridge', struct('beta',beta,'lambda',lambda));
info = struct('muZ',muZ,'sgZ',sgZ,'cfg',D,'trainMaskUsed',tr,'valMaskUsed',isVal, ...
    'note','Validation uses recursive roll-out (lags filled with previous predictions).');
end


function M = compute_metrics_full(Pm, Ph, Pnom)
% Compute metrics exactly like your snippet, robust to NaNs.

Pm = Pm(:);
Ph = Ph(:);

e = Pm - Ph;
M.K = sum(isfinite(e));

% RMSE, MAE, MBE
M.rmse = sqrt(mean(e.^2, 'omitnan'));
M.mae  = mean(abs(e), 'omitnan');
M.mbe  = mean(e, 'omitnan');

% MAPE (avoid division by 0)
epsP = 1e-6;
idx_mape = (Pm > epsP) & isfinite(Pm) & isfinite(Ph);
M.mape = mean(abs((Pm(idx_mape) - Ph(idx_mape)) ./ Pm(idx_mape)), 'omitnan') * 100;

% NRMSE (normalized by variance about mean)
Pm_bar = mean(Pm, 'omitnan');
den = sum((Pm - Pm_bar).^2, 'omitnan');
num = sum((Pm - Ph).^2, 'omitnan');

if den > 0
    M.nrmse = sqrt(num / den);
else
    M.nrmse = nan;
end

% R^2 (as in your definition)
M.r2 = 1 - M.nrmse^2;

% Normalized-by-nominal metrics
M.rmse_np = M.rmse / Pnom;
M.mape_np = mean(abs((Pm(idx_mape) - Ph(idx_mape)) / Pnom), 'omitnan'); % unitless
end
