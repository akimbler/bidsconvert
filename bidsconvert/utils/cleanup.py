"""Utilities used by other modules in cis-bidsify."""
import shutil
import tarfile
from pathlib import Path
import pandas as pd
import numpy as np
import pydicom
from dateutil.parser import parse


def load_dicomdir_metadata(dicomdir):
    """Grab data from dicom directory of a given type (tar, tar.gz, directory).
    Parameters
    ----------
    dicomdir: Directory containing dicoms for processing
    Returns
    -------
    data : dicom header
        DICOM information from first dicom in directory.
    """
    if dicomdir.is_file() and dicomdir.suffix in (".gz", ".tar"):
        open_type = "r"
        if dicomdir.suffix == ".gz":
            open_type = "r:gz"
        with tarfile.open(dicomdir, open_type) as tar:
            dicoms = [mem for mem in tar.getmembers() if mem.name.endswith(".dcm")]
            f_obj = tar.extractfile(dicoms[0])
            data = pydicom.read_file(f_obj)
    elif dicomdir.is_dir():
        dcm_files = list(Path(dicomdir).glob("**/*.dcm"))
        f_obj = dcm_files[0].as_posix()
        data = pydicom.read_file(f_obj)
    return data


def clean_tempdirs(output_dir, sub, ses):
    """Clean up working directories (.heudiconv and .tmp).
    If all work is complete, this will return the
    directory to BIDS standard (removing .heudiconv and .tmp directories).
    Parameters
    ----------
    output_dir: Path object of bids directory
    sub: Subject ID
    ses: Session ID, if required
    """
    for root in [".heudiconv", ".tmp"]:
        if ses:
            if root == ".heudiconv":
                print(
                    "Removing Temp Directory: ", output_dir / root / sub / f"ses-{ses}"
                )
                shutil.rmtree(output_dir / root / sub / f"ses-{ses}")
            else:
                print("Removing Temp Directory: ", output_dir / root / sub / ses)
                shutil.rmtree(output_dir / root / sub / ses)
        if (output_dir / root / sub).is_dir():
            print("Removing Temp Directory: ", output_dir / root / sub)
            shutil.rmtree(output_dir / root / sub)
        if (output_dir / root).is_dir() and not next(
            (output_dir / root).iterdir(), None
        ):
            print("Removing Temp Directory: ", output_dir / root)
            shutil.rmtree((output_dir / root))


def update_participants(output_dir, dicom_dir, subject):
    participants_file = output_dir / "participants.tsv"
    if participants_file.exists():
        participant_df = pd.read_table(participants_file, index_col="participant_id")
        data = load_dicomdir_metadata(dicom_dir)
        participant_id = f"sub-{subject}"
        if data.get("PatientAge"):
            age = data.PatientAge.replace("Y", "")
            try:
                age = int(age)
            except ValueError:
                age = np.nan
        elif data.get("PatientBirthDate"):
            age = parse(data.StudyDate) - parse(data.PatientBirthDate)
            age = np.round(age.days / 365.25, 2)
        else:
            age = np.nan

        additional_data = pd.DataFrame(
            columns=["age", "sex", "weight"],
            data=[[age, data.PatientSex, data.PatientWeight]],
            index=[participant_id],
        )

        missing_cols = [
            col for col in additional_data.columns if col not in participant_df.columns
        ]
        for mc in missing_cols:
            participant_df[mc] = np.nan
        if participant_id not in participant_df.index.values:
            participant_df.loc[participant_id] = np.nan

        participant_df.update(additional_data, overwrite=True)
        participant_df.sort_index(inplace=True)
        participant_df.to_csv(
            participants_file,
            sep="\t",
            na_rep="n/a",
            line_terminator="\n",
            index_label="participant_id",
        )

