import numpy as np
import pandas as pd
import plotly.express as px
import streamlit as st

# Set page config for full width layout
st.set_page_config(layout="wide")

st.title("Torque Analysis Parallel Coordinates Plot")

# User-configurable sliders
st.write("### Configure Parameters")
param_cols = st.columns(3)
with param_cols[0]:
    mass = st.slider("Mass (kg)", 10, 200, 50)
with param_cols[1]:
    rolling_resistance = st.slider("Rolling Resistance", 0.001, 0.1, 0.02, step=0.001)
with param_cols[2]:
    error_tolerance = st.slider("Error Tolerance (%)", 0.0, 1.0, 0.02, step=0.01) / 100  # Convert percentage to fraction

df_global = None  # Placeholder for precomputed data

def calculate_torque_vectorized(accelerations, wheel_radii, rolling_resistance, mass, incline_angles):
    g = 9.81
    num_wheels = 4
    incline_angles_rad = np.radians(incline_angles)
    incline_force = mass * g * np.sin(incline_angles_rad)[:, None, None]
    rolling_force = rolling_resistance * mass * g * np.cos(incline_angles_rad)[:, None, None]
    acceleration_force = mass * accelerations[None, :, None]
    total_force = (rolling_force + acceleration_force + incline_force) / num_wheels
    torques = total_force * wheel_radii[None, None, :]
    return torques

def parallel_compute():
    global df_global
    if df_global is not None:
        return df_global  # Return precomputed dataset

    wheel_radii = np.linspace(0, 0.5, 50)
    accelerations = np.linspace(0, 1.5, 50)
    incline_angles = np.linspace(0, 30, 50)

    data = []
    torques = calculate_torque_vectorized(accelerations, wheel_radii, rolling_resistance, mass, incline_angles)
    for i, angle in enumerate(incline_angles):
        for j, accel in enumerate(accelerations):
            for k, radius in enumerate(wheel_radii):
                data.append([torques[i, j, k], accel, radius, angle])

    df_global = pd.DataFrame(data, columns=['Torque (Nm)', 'Acceleration (m/s²)', 'Wheel Radius (m)', 'Incline Angle (degrees)'])
    return df_global

def create_figure(df):
    fig = px.parallel_coordinates(
        df,
        dimensions=['Torque (Nm)', 'Acceleration (m/s²)', 'Wheel Radius (m)', 'Incline Angle (degrees)'],
        color='Torque (Nm)',
        color_continuous_scale=px.colors.sequential.Plasma
    )
    fig.update_layout(
        autosize=True,
        height=700,
        margin=dict(l=20, r=20, t=50, b=50)
    )
    return fig

df = parallel_compute()
st.write("### Select Filters")

# Use a 3-column layout for sliders with appropriate spacing
filters_container = st.container()
with filters_container:
    filter_cols = st.columns(3)
    dimensions = ['Torque (Nm)', 'Acceleration (m/s²)', 'Wheel Radius (m)', 'Incline Angle (degrees)']
    filters = {}
    for i, dim in enumerate(dimensions):
        with filter_cols[i % 3]:  # Distribute sliders across 3 columns
            min_val, max_val = df[dim].min(), df[dim].max()
            filters[dim] = st.slider(f"{dim}", min_val, max_val, (min_val, max_val))

# Apply filters to dataframe
filtered_df = df.copy()
for dim, (min_val, max_val) in filters.items():
    if min_val == max_val:  # Handle single value selection
        tolerance = (df[dim].max() - df[dim].min()) * error_tolerance  # User-configurable tolerance
        filtered_df = filtered_df[(filtered_df[dim] >= min_val - tolerance) & (filtered_df[dim] <= max_val + tolerance)]
    else:
        filtered_df = filtered_df[(filtered_df[dim] >= min_val) & (filtered_df[dim] <= max_val)]

# Display the figure in a wider container
fig = create_figure(filtered_df)
st.plotly_chart(fig, use_container_width=True)

st.write("### Filtered Data Table")
st.dataframe(filtered_df, use_container_width=True)

