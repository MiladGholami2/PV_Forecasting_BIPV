clearvars; close all; clc

%% ====================== LOCATION ======================
lat = 39.5013;
lon = -8.7677;     % lon>0 East; this is West (ok if cs_In expects it)
alt = 94;
Location = [lat, lon, alt];

%% ====================== LOAD LOCAL DATASET (.mat) ======================
matfile = 'dataSetSardegna-DC-02.mat';
S = load(matfile);

% ---- Build timestamps (UTC) ----
yr      = S.measure.time.year(:);
doyFrac = S.measure.time.time(:);     % day-of-year + fraction
t = datetime(yr,1,1,0,0,0,'TimeZone','UTC') + days(doyFrac - 1);
t = datetime(yr,1,1,0,0,0,'TimeZone','UTC') + days(doyFrac - 1);
t = datetime(t,'Format','dd-MMM-yyyy HH:mm:ss','TimeZone','UTC');
t = dateshift(t,'start','second');


% ---- Signals (both sources) ----
DNI_meas = S.measure.I(:);     % measured DNI [W/m^2]
Ta_meas  = S.measure.T(:);     % measured air temp [°C]
Pmeas    = S.measure.P(:);     % measured power (optional, units unknown)

DNI_fcst = S.forecast.I(:);    % forecast DNI [W/m^2]
Ta_fcst  = S.forecast.T(:);    % forecast air temp [°C]

%% ====================== RAW (pre-15min) PLOTS: DNI & Ta ======================
fs_raw = 18;

tRawPlotStart = datetime(2012,4,16,0,0,0,'TimeZone','UTC');
tRawPlotEnd   = datetime(2012,5,1,23,59,59,'TimeZone','UTC');
idxRaw = (t >= tRawPlotStart) & (t <= tRawPlotEnd);

dayTicksRaw = (dateshift(tRawPlotStart,'start','day') : days(1) : ...
               dateshift(tRawPlotEnd,'start','day')).';

figure('Name','RAW DNI (Measured vs Forecast) - pre-15min','Position',[80 720 1500 360]);
clf; hold on; grid on;
plot(t(idxRaw), DNI_meas(idxRaw), 'b-','LineWidth',1.4,'DisplayName','$G_{\mathrm{DNI}}(t)$');
plot(t(idxRaw), DNI_fcst(idxRaw), 'r-','LineWidth',1.4,'DisplayName','$\tilde{G}_{\mathrm{DNI}}(t)$');
ylabel('DNI [W/m$^2$]','Interpreter','latex','FontSize',fs_raw);
legend('show','Location','best','Interpreter','latex','FontSize',fs_raw);
ax=gca; ax.FontSize=fs_raw; ax.TickLabelInterpreter='latex';
ax.XTick = dayTicksRaw; ax.XAxis.TickLabelFormat = 'MMM dd';
xlim([tRawPlotStart tRawPlotEnd]); set(gcf,'Color','w');

figure('Name','RAW Ta (Measured vs Forecast) - pre-15min','Position',[80 300 1500 360]);
clf; hold on; grid on;
plot(t(idxRaw), Ta_meas(idxRaw), 'b-','LineWidth',1.4,'DisplayName','$T_a(t)$');
plot(t(idxRaw), Ta_fcst(idxRaw), 'r-','LineWidth',1.4,'DisplayName','$\tilde{T}_a(t)$');
ylabel('Temperature [$^\circ$C]','Interpreter','latex','FontSize',fs_raw);
legend('show','Location','best','Interpreter','latex','FontSize',fs_raw);
ax=gca; ax.FontSize=fs_raw; ax.TickLabelInterpreter='latex';
ax.XTick = dayTicksRaw; ax.XAxis.TickLabelFormat = 'MMM dd';
xlim([tRawPlotStart tRawPlotEnd]); set(gcf,'Color','w');

%% ====================== BUILD TIMETABLES ======================
TT_meas = timetable(t, DNI_meas, Ta_meas, Pmeas, 'VariableNames', {'DNI','T2M','PMEAS'});
TT_fcst = timetable(t, DNI_fcst, Ta_fcst, Pmeas, 'VariableNames', {'DNI','T2M','PMEAS'});

TT_meas = sortrows(TT_meas);
TT_fcst = sortrows(TT_fcst);

% remove duplicates consistently (use measured time axis as reference)
[~, ia] = unique(TT_meas.Properties.RowTimes, 'stable');
TT_meas = TT_meas(ia,:);
TT_fcst = TT_fcst(ia,:);

% regularize both to 15-min grid
TT15_meas = retime(TT_meas, 'regular', 'pchip', 'TimeStep', minutes(15));
TT15_fcst = retime(TT_fcst, 'regular', 'pchip', 'TimeStep', minutes(15));

rt = TT15_meas.Properties.RowTimes;  % common grid

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

%% ====================== PV CONFIG =============================
num_pvs    = 2;
tilt_deg   = [50, 30];
az_deg     = [15, -70];
kw_dc_arr  = [3, 5];     % kW DC rating per PV array
mod_type   = [0, 0];     % 0 standard, 1 premium, 2 thin-film

%% ====================== RUN BOTH MODES ================================
Modes = {'measured','forecast'};
R = struct();

for rr = 1:numel(Modes)
    mode = Modes{rr};
    fprintf('\n==================== MODE: %s ====================\n', upper(mode));

    if strcmp(mode,'measured')
        T = Tmeas;
    else
        T = Tfcst;
    end

    nT = height(T);

    %% ===== Clear-sky DNI + sun geometry (your cs_In) =====
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

    isDay = (s_alt > 0);

    % mode meteo
    DNI_act = T.DNI;   DNI_act(~isDay) = 0;
    Ta      = T.T2M;   % [°C]

    %% ===== Per PV: POA + PVWatts-like power (kW, mode-consistent) =====
    pv_POA_act = zeros(nT, num_pvs);  % [W/m^2]
    pv_POA_cs  = zeros(nT, num_pvs);  % [W/m^2]
    pv_P_dc    = zeros(nT, num_pvs);  % [kW]
    pv_P_dc_cs = zeros(nT, num_pvs);  % [kW]

    for pv = 1:num_pvs
        % module parameters
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
        cos_alpha(~isfinite(cos_alpha)) = 0;
        cos_alpha = max(cos_alpha, 0);

        POA_act = max(DNI_act   .* cos_alpha, 0);   % [W/m^2]
        POA_cs  = max(DNI_cs_my .* cos_alpha, 0);   % [W/m^2]

        % PVWatts-like DC power in kW (THIS IS THE KEY UNIT FIX)
        Pdc_rated_kW = kw_dc_arr(pv);               % [kW]

        Tcell_act = Tmeas.T2M + ( max((Tmeas.DNI)   .* cos_alpha, 0)/800) * (NOCT - 20);
        Pdc_act   = Pdc_rated_kW .* ( max((Tmeas.DNI)   .* cos_alpha, 0)/1000) .* (1 + gamma.*(Tcell_act - 25));


        Tcell_cs  = Ta + (POA_cs/800) * (NOCT - 20);    % [°C]
        Pdc_cs    = Pdc_rated_kW .* (POA_cs/1000) .* (1 + gamma*(Tcell_cs - 25));

        Pdc_act = max(Pdc_act, 0);  Pdc_act(~isDay) = 0;
        Pdc_cs  = max(Pdc_cs,  0);  Pdc_cs(~isDay)  = 0;

        pv_POA_act(:,pv) = POA_act;
        pv_POA_cs(:,pv)  = POA_cs;
        pv_P_dc(:,pv)    = Pdc_act;
        pv_P_dc_cs(:,pv) = Pdc_cs;
    end

    % Reference aggregate power (kW)
    Ptot_true = sum(pv_P_dc, 2);

    %% ===== Build design matrices A_all and A_cs (mode-consistent Ta) =====
    Mpv = num_pvs;
    A_all = zeros(nT, 3*Mpv);
    A_cs  = zeros(nT, 3*Mpv);

    for p = 1:Mpv
        ix = (p-1)*3 + (1:3);
        Ii  = pv_POA_act(:,p);   % [W/m^2]
        Iic = pv_POA_cs(:,p);    % [W/m^2]

        A_all(:,ix(1)) = Ii;
        A_all(:,ix(2)) = Ii.^2;
        A_all(:,ix(3)) = Ii .* Ta(:);

        A_cs(:,ix(1))  = Iic;
        A_cs(:,ix(2))  = Iic.^2;
        A_cs(:,ix(3))  = Iic .* Ta(:);      % FIX: do NOT force forecast Ta here
    end

    %% ===== Training mask (remove deep night / very low cs POA) =====
    POAcs_sum = sum(pv_POA_cs, 2);
    % Exclude night-ish points from training (simple robust mask)
    Pthr_1 = max(pv_POA_cs(:,1))*0.07;
    Pthr_2 = max(pv_POA_cs(:,2))*0.07;
    bad_idx = (pv_POA_cs(:,1) < Pthr_1) & (pv_POA_cs(:,2) < Pthr_2);
   
    mask_train = isTrain & ~bad_idx;

    %% ===== Solve LP on TRAIN rows =====
    [theta_lp, P_cs_est, obj_value] = solve_LP(A_cs(mask_train,:), Ptot_true(mask_train));
    % --- Clear-sky envelope on the FULL series (not only masked TRAIN rows)
Ptot_cs_full = A_cs * theta_lp;      % kW (clear-sky envelope)
Ptot_cs_full = max(Ptot_cs_full,0);
Ptot_cs_full(~isDay) = 0;

    % Full-series LP reconstruction (kW)
    Ptot_lp_full = A_all * theta_lp;
    Ptot_lp_full = max(Ptot_lp_full, 0);
    Ptot_lp_full(~isDay) = 0;

    %% ===== Print μ =====
    mu_LP = reshape(theta_lp, 3, Mpv);
    fprintf('\nLP coefficients (kW formulation):\n');
    for p = 1:Mpv
        fprintf('PV%-2d :  mu1 = %+ .6e   mu2 = %+ .6e   mu3 = %+ .6e\n', ...
            p, mu_LP(1,p), mu_LP(2,p), mu_LP(3,p));
    end
    mu_tbl = array2table(mu_LP.', 'VariableNames', {'mu1','mu2','mu3'});
    mu_tbl.PV = (1:Mpv).';
    mu_tbl = movevars(mu_tbl, 'PV', 'Before', 1);
    disp(mu_tbl);

    %% ===== Per-PV power from LP (kW) =====
    Ppv_lp = zeros(nT, Mpv);
    for p = 1:Mpv
        Ii = pv_POA_act(:,p);
        Ppv_lp(:,p) = mu_LP(1,p).*Ii + mu_LP(2,p).*Ii.^2 + mu_LP(3,p).*Ii.*Ta(:);
    end
    Ppv_lp = max(Ppv_lp,0);
    Ppv_lp(~isDay,:) = 0;

    %% ===== Validation metrics (kW) =====
    Pm = Ptot_true(isVal);
    Ph = Ptot_lp_full(isVal);
    e  = Pm - Ph;

    rmse_val = sqrt(mean(e.^2,'omitnan'));
    mae_val  = mean(abs(e),'omitnan');
    mbe_val  = mean(e,'omitnan');

    epsP = 1e-6;
    idx_mape = (Pm > epsP) & isfinite(Pm) & isfinite(Ph);
    mape_val = mean(abs((Pm(idx_mape)-Ph(idx_mape))./Pm(idx_mape)),'omitnan') * 100;

    Pm_bar = mean(Pm,'omitnan');
    den = sum((Pm - Pm_bar).^2,'omitnan');
    num = sum((Pm - Ph).^2,'omitnan');
    nrmse_val = sqrt(num/den);
    r2_val = 1 - nrmse_val^2;

    Pnom = sum(kw_dc_arr);            % kW (since outputs are kW)
    rmse_np_val = rmse_val / Pnom;
    mape_np_val = mean(abs((Pm(idx_mape)-Ph(idx_mape))/Pnom),'omitnan');

    fprintf(['LP Validation (VAL) — RMSE: %.4f kW | MAE: %.4f kW | MBE: %.4f kW | ' ...
             'MAPE: %.3f %% | NRMSE: %.6f | R^2: %.6f | RMSE_NP: %.6f | MAPE_NP: %.6f\n'], ...
             rmse_val, mae_val, mbe_val, mape_val, nrmse_val, r2_val, rmse_np_val, mape_np_val);

    %% ===== Save in struct =====
    R.(mode).Time     = T.Time;
    R.(mode).DNI      = T.DNI;
    R.(mode).Ta       = Ta;
    R.(mode).Ptrue    = Ptot_true;       % kW
    R.(mode).Plp      = Ptot_lp_full;    % kW
    R.(mode).POAcs    = pv_POA_cs;       % W/m^2
    R.(mode).POAact   = pv_POA_act;      % W/m^2
    R.(mode).pv_P_dc  = pv_P_dc;         % kW
    R.(mode).Ppv_lp   = Ppv_lp;          % kW
    R.(mode).theta_lp = theta_lp;
    R.(mode).mu_tbl   = mu_tbl;

    R.(mode).rmse    = rmse_val;
    R.(mode).mae     = mae_val;
    R.(mode).mbe     = mbe_val;
    R.(mode).mape    = mape_val;
    R.(mode).nrmse   = nrmse_val;
    R.(mode).r2      = r2_val;
    R.(mode).rmse_np = rmse_np_val;
    R.(mode).mape_np = mape_np_val;
end

%% ====================== SIMPLE COMPARISON PLOT (VAL) ======================
fs = 26;
dataYear = year(R.measured.Time(find(isVal,1,'first')));

tValPlotStart = datetime(dataYear, 4,16,0,0,0,'TimeZone','UTC');
tValPlotEnd   = datetime(dataYear, 4,22,23,59,59,'TimeZone','UTC');
isValPlotT = (R.measured.Time >= tValPlotStart) & (R.measured.Time <= tValPlotEnd);

dayTicks = (dateshift(tValPlotStart,'start','day') : days(1) : ...
            dateshift(tValPlotEnd,'start','day')).';

figure('Name','Total PV Power (VAL): measured-mode (Actual vs LP)','Position',[80 650 1500 360]);
clf; hold on; grid on;
stairs(R.measured.Time(isValPlotT), R.measured.Ptrue(isValPlotT), 'b-','LineWidth',2.0,'DisplayName','$P_{\mathrm{tot}}(t)$');
stairs(R.measured.Time(isValPlotT), R.measured.Plp(isValPlotT),   'r-','LineWidth',2.0,'DisplayName','$\hat{P}_{\mathrm{tot}}(t)$');
ylabel('Power [kW]','Interpreter','latex','FontSize',fs);
legend('show','Location','best','Interpreter','latex','FontSize',fs);
ax=gca;
ax.FontSize = fs;
ax.TickLabelInterpreter = 'latex';
ax.XAxis.TickLabelFormat = 'MMM dd';
ax.XAxis.SecondaryLabel.String = '';

figure('Name','Total PV Power (VAL): forecast-mode (Actual vs LP)','Position',[80 250 1500 360]);
clf; hold on; grid on;
stairs(R.forecast.Time(isValPlotT), R.forecast.Ptrue(isValPlotT), 'b-','LineWidth',2.0,'DisplayName','${P}_{\mathrm{tot}}(t)$');
stairs(R.forecast.Time(isValPlotT), R.forecast.Plp(isValPlotT),   'r-','LineWidth',2.0,'DisplayName','${\tilde{P}}_{\mathrm{tot}}(t)$');
ylabel('Power [kW]','Interpreter','latex','FontSize',fs);
legend('show','Location','best','Interpreter','latex','FontSize',fs);
ax=gca;
ax.FontSize = fs;
ax.TickLabelInterpreter = 'latex';
ax.XAxis.TickLabelFormat = 'MMM dd';
ax.XAxis.SecondaryLabel.String = '';
ylim([0 8]);
 set(gcf,'Color','w');


 tPlotStart = datetime(dataYear, 2, 2, 0, 0, 0, 'TimeZone','UTC');
tPlotEnd   = datetime(dataYear, 2,17,23,59,59,'TimeZone','UTC');
idxTrainPlot = (R.measured.Time >= tPlotStart) & (R.measured.Time <= tPlotEnd);


 % ===== (2) Total power: Ptot vs Ptilde in ONE figure =====
figure('Name','TRAIN: $P_{\mathrm{tot}}(t)$ vs $\tilde{P}_{\mathrm{tot}}(t)$','Position',[100 250 1500 420]);
clf; hold on; grid on;

stairs(R.measured.Time(idxTrainPlot), R.measured.Ptrue(idxTrainPlot), 'b-', 'LineWidth', 2.2);
%stairs(R.forecast.Time(idxTrainPlot), R.forecast.Ptrue(idxTrainPlot), 'r-', 'LineWidth', 2.2);

ylabel('Power [kW]','Interpreter','latex','FontSize',fs);
legend({'${P}_{\mathrm{tot}}(t)$'},'Interpreter','latex','FontSize',fs,'Location','best');

ax=gca;
ax.FontSize = fs;
ax.TickLabelInterpreter = 'latex';
ax.XAxis.TickLabelFormat = 'MMM dd';
ax.XAxis.SecondaryLabel.String = '';
set(gcf,'Color','w');


%% ===== FIGURE: clear-sky envelope is tight on a subset (one day) =====
fs_fig = 26;

% --- pick a representative TRAIN day automatically (highest daily peak)
train_times = T.Time(isTrain);
train_days  = unique(dateshift(train_times,'start','day'));

bestDay = train_days(1);
bestPeak = -inf;

for dd = 1:numel(train_days)
    d0 = train_days(dd);
    d1 = d0 + days(1);
    idxD = (T.Time >= d0) & (T.Time < d1) & isTrain;
    if any(idxD)
        pk = max(Ptot_true(idxD),[],'omitnan');
        if pk > bestPeak
            bestPeak = pk;
            bestDay = d0;
        end
    end
end

% --- indices for that day (TRAIN only)
t0 = bestDay;
t1 = bestDay + days(1);
idxDay = (T.Time >= t0) & (T.Time < t1) & isTrain;

% --- tight set: where envelope equals measured (within tolerance)
gap_full = Ptot_cs_full - Ptot_true;     % should be >= 0 (envelope)
tol = 1e-3;                              % kW tolerance (adjust if needed)
idxTight = idxDay & isfinite(gap_full) & (abs(gap_full) <= tol);

figure('Name','One-day CS envelope tightness','Position',[100 200 1600 450]);
clf; hold on; grid on;

stairs(T.Time(idxDay), Ptot_true(idxDay),   'b-','LineWidth',2.2, ...
    'DisplayName','$P_{\mathrm{tot}}(t)$');
stairs(T.Time(idxDay), Ptot_cs_full(idxDay),'k-','LineWidth',2.2, ...
    'DisplayName','$P_{\mathrm{tot}}^{\mathrm{cs}}(t\mid\hat{\theta})$');

% mark the tight subset \hat{T}^{cs}
plot(T.Time(idxTight), Ptot_true(idxTight), 'ro', 'MarkerSize',6, ...
    'LineWidth',1.8, 'DisplayName','$t \in \hat{\mathcal{T}}^{\mathrm{cs}}$');

ylabel('Power [kW]','Interpreter','latex','FontSize',fs_fig);
xlabel('Time','Interpreter','latex','FontSize',fs_fig);
% title(sprintf('Clear-sky envelope tightness on %s (TRAIN)', datestr(t0,'dd-mmm-yyyy')), ...
    % 'Interpreter','none');

legend('show','Location','best','Interpreter','latex','FontSize',fs_fig);

ax = gca;
ax.FontSize = fs_fig;
ax.TickLabelInterpreter = 'latex';
ax.XAxis.TickLabelFormat = 'HH:mm';
%ax.XAxis.SecondaryLabel.String = '';
xlim([t0 t1]);
set(gcf,'Color','w');

%% ===== FIGURE: clear-sky envelope tightness (April 15, 2012) =====
%% ===== FIGURE: clear-sky envelope tightness (April 15, 2012) =====
fs_fig = 26;

% --- Fixed day
t0 = datetime(2012,3,29,0,0,0,'TimeZone','UTC');
t1 = t0 + days(1);

% IMPORTANT: April 15 is in VAL for your current split, so do NOT force isTrain
idxDay = (T.Time >= t0) & (T.Time < t1);

if ~any(idxDay)
    error('No samples found on April 15, 2012 (check dataset coverage/timezone).');
end

% --- tight set: envelope equals measured (within tolerance)
gap_full = Ptot_cs_full - Ptot_true;     % should be >= 0 if envelope holds perfectly
tol = 5e-3;                              % kW tolerance (loosen a bit for numerical noise)
idxTight = idxDay & isfinite(gap_full) & (abs(gap_full) <= tol);

figure('Name','CS envelope tightness - 15 April 2012','Position',[100 200 1600 450]);
clf; hold on; grid on;

stairs(T.Time(idxDay), Ptot_true(idxDay), ...
    'b-','LineWidth',2.2,'DisplayName','$P_{\mathrm{tot}}(t)$');

stairs(T.Time(idxDay), Ptot_cs_full(idxDay), ...
    'k-','LineWidth',2.2,'DisplayName','$P_{\mathrm{tot}}^{\mathrm{cs}}(t\mid\hat{\theta})$');

plot(T.Time(idxTight), Ptot_true(idxTight), ...
    'ro','MarkerSize',6,'LineWidth',1.8, ...
    'DisplayName','$t \in \hat{\mathcal{T}}^{\mathrm{cs}}$');

ylabel('Power [kW]','Interpreter','latex','FontSize',fs_fig);
xlabel('Time','Interpreter','latex','FontSize',fs_fig);
%title('Clear-sky envelope tightness — 15-Apr-2012','Interpreter','none');

legend('show','Location','best','Interpreter','latex','FontSize',fs_fig);

ax = gca;
ax.FontSize = fs_fig;
ax.TickLabelInterpreter = 'latex';
ax.XAxis.TickLabelFormat = 'HH:mm';
ax.XAxis.SecondaryLabel.String = '';
xlim([t0 t1]);
set(gcf,'Color','w');



fprintf('\n=== FINAL METRICS (VAL) ===\n');
fprintf(['Measured-meteo: RMSE=%.4f kW | MAE=%.4f kW | MBE=%.4f kW | MAPE=%.3f %% | ' ...
         'NRMSE=%.6f | R^2=%.6f | RMSE_NP=%.6f | MAPE_NP=%.6f\n'], ...
         R.measured.rmse, R.measured.mae, R.measured.mbe, R.measured.mape, ...
         R.measured.nrmse, R.measured.r2, R.measured.rmse_np, R.measured.mape_np);

fprintf(['Forecast-meteo: RMSE=%.4f kW | MAE=%.4f kW | MBE=%.4f kW | MAPE=%.3f %% | ' ...
         'NRMSE=%.6f | R^2=%.6f | RMSE_NP=%.6f | MAPE_NP=%.6f\n'], ...
         R.forecast.rmse, R.forecast.mae, R.forecast.mbe, R.forecast.mape, ...
         R.forecast.nrmse, R.forecast.r2, R.forecast.rmse_np, R.forecast.mape_np);

fprintf('\nDone.\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% LOCAL FUNCTION: LP solve (envelope) with supervisor ratio bounds
% P is in kW; I is in W/m^2
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


function [mu_est,P_cs_est,obj_value] = solve_LP(A_cs, P)

    yalmip('clear')

    [n,k] = size(A_cs);
    theta = sdpvar(k,1);
    P_cs_est = A_cs * theta;

    % Envelope: P_cs_est >= P
    gap = P_cs_est - P(:);

    Objective   = sum(gap);
    Constraints = [gap >= 0];

    % =====================================================
    % Physical constraints
    % =====================================================
    Mpv = k/3;                        % number of PVs
    eps_mu1 = 1e-9;                   % IMPORTANT for kW scaling

    % Supervisor bounds (ratio constraints)
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

        Constraints = [Constraints, mu1 >= eps_mu1];

        % ratio bounds implemented as linear constraints
        Constraints = [Constraints, mu2 >= eta2_min * mu1, mu2 <= eta2_max * mu1];
        Constraints = [Constraints, mu3 >= eta3_min * mu1, mu3 <= eta3_max * mu1];
    end

    ops = sdpsettings('solver','gurobi','verbose',1);

    sol = optimize(Constraints, Objective, ops);
    if sol.problem ~= 0
        error("LP failed: %s", sol.info);
    end

    mu_est    = value(theta);
    P_cs_est  = value(P_cs_est);
    obj_value = value(Objective);
end
